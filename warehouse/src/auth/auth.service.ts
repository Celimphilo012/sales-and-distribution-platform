import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';
import { PrismaService } from '../common/prisma/prisma.service';
import { parseDurationMs } from '../common/utils/duration.util';
import { resolveEffectivePermissionKeys } from '../common/utils/effective-permissions.util';
import { LoginDto } from './dto/login.dto';

interface RefreshPayload {
  sub: string;
  jti: string;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {}

  async login(dto: LoginDto) {
    const user = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (!user || user.status !== 'ACTIVE') {
      throw new UnauthorizedException('Invalid email or password');
    }

    const passwordValid = await argon2.verify(user.passwordHash, dto.password);
    if (!passwordValid) {
      throw new UnauthorizedException('Invalid email or password');
    }

    const accessToken = await this.signAccessToken(user.id, user.email);
    const { token: refreshToken } = await this.issueRefreshToken(user.id);

    return {
      accessToken,
      refreshToken,
      user: { id: user.id, email: user.email, fullName: user.fullName },
    };
  }

  async refresh(rawRefreshToken: string) {
    const payload = await this.verifyRefreshToken(rawRefreshToken);

    const existing = await this.prisma.refreshToken.findUnique({ where: { id: payload.jti } });
    if (
      !existing ||
      existing.userId !== payload.sub ||
      existing.revokedAt ||
      existing.expiresAt.getTime() < Date.now()
    ) {
      throw new UnauthorizedException('Refresh token is no longer valid');
    }

    const hashMatches = await argon2.verify(existing.tokenHash, rawRefreshToken);
    if (!hashMatches) {
      throw new UnauthorizedException('Refresh token is no longer valid');
    }

    const user = await this.prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user || user.status !== 'ACTIVE') {
      throw new UnauthorizedException('Account is no longer active');
    }

    const newAccessToken = await this.signAccessToken(user.id, user.email);
    const { token: newRefreshToken, id: newRowId } = await this.issueRefreshToken(user.id);

    await this.prisma.refreshToken.update({
      where: { id: existing.id },
      data: { revokedAt: new Date(), replacedByTokenId: newRowId },
    });

    return {
      accessToken: newAccessToken,
      refreshToken: newRefreshToken,
      user: { id: user.id, email: user.email, fullName: user.fullName },
    };
  }

  /**
   * The caller's own identity + effective permissions — always resolved
   * from the authenticated `userId` (taken from the JWT), never an
   * arbitrary id, so no `users.manage`/`roles.manage` permission is needed
   * to call this. Permissions are resolved via the exact same helper
   * `PermissionGuard` uses, so this can never disagree with what the guards
   * actually enforce.
   */
  async me(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        fullName: true,
        status: true,
        userRoles: { select: { role: { select: { id: true, name: true } } } },
      },
    });
    if (!user) {
      throw new UnauthorizedException('User not found');
    }

    const { userRoles, ...profile } = user;
    const permissions = await resolveEffectivePermissionKeys(this.prisma, userId);

    return {
      ...profile,
      roles: userRoles.map((ur) => ur.role),
      permissions,
    };
  }

  async logout(rawRefreshToken: string) {
    try {
      const payload = await this.verifyRefreshToken(rawRefreshToken);
      await this.prisma.refreshToken.updateMany({
        where: { id: payload.jti, revokedAt: null },
        data: { revokedAt: new Date() },
      });
    } catch {
      // Logout is idempotent: an already-invalid token is not an error.
    }
    return { success: true };
  }

  private async signAccessToken(userId: string, email: string) {
    return this.jwtService.signAsync(
      { sub: userId, email },
      {
        secret: this.configService.get<string>('JWT_ACCESS_SECRET'),
        expiresIn: this.configService.get<string>('JWT_ACCESS_EXPIRES_IN'),
      },
    );
  }

  private async issueRefreshToken(userId: string): Promise<{ token: string; id: string }> {
    const refreshExpiresIn = this.configService.get<string>('JWT_REFRESH_EXPIRES_IN') ?? '7d';
    const expiresAt = new Date(Date.now() + parseDurationMs(refreshExpiresIn));

    const row = await this.prisma.refreshToken.create({
      data: { userId, tokenHash: 'pending', expiresAt },
    });

    const token = await this.jwtService.signAsync(
      { sub: userId, jti: row.id } satisfies RefreshPayload,
      {
        secret: this.configService.get<string>('JWT_REFRESH_SECRET'),
        expiresIn: refreshExpiresIn,
      },
    );

    const tokenHash = await argon2.hash(token);
    await this.prisma.refreshToken.update({ where: { id: row.id }, data: { tokenHash } });

    return { token, id: row.id };
  }

  private async verifyRefreshToken(rawRefreshToken: string): Promise<RefreshPayload> {
    try {
      return await this.jwtService.verifyAsync<RefreshPayload>(rawRefreshToken, {
        secret: this.configService.get<string>('JWT_REFRESH_SECRET'),
      });
    } catch {
      throw new UnauthorizedException('Invalid or expired refresh token');
    }
  }
}
