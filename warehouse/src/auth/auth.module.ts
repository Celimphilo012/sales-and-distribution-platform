import { Module } from '@nestjs/common';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';

// JwtService comes from the global JwtModule registered in AppModule.
// Access and refresh tokens are signed/verified with different secrets
// passed explicitly per call in AuthService/AuthGuard.
@Module({
  controllers: [AuthController],
  providers: [AuthService],
  exports: [AuthService],
})
export class AuthModule {}
