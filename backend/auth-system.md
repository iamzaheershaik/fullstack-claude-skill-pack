# Auth System — Claude Skill

> Implement production-grade authentication and authorization. JWT, OAuth 2.0, RBAC, session management, security hardening. MERN-first with portable patterns.

---

## Core Directives

1. **Auth is infrastructure, not a feature.** Get it right before building anything else.
2. **Defense in depth.** Never rely on a single layer — validate tokens, check permissions, verify ownership.
3. **Secrets are sacred.** Never log tokens, passwords, or PII. Never expose internal auth errors to clients.
4. **Fail closed.** If auth state is ambiguous, deny access.

---

## 1 · Authentication Architecture

### Token Strategy (Default: Dual Token)
```
Access Token  → JWT, 15min TTL, stored in memory (JS variable)
Refresh Token → Opaque (crypto.randomBytes), 7d TTL, httpOnly + Secure + SameSite=Strict cookie
```

### Why This Pattern
| Concern | Solution |
|---|---|
| XSS can't steal tokens | Access token never in localStorage/cookies |
| CSRF can't use tokens | Access token sent via Authorization header |
| Token theft limited | 15min window, rotation on refresh |
| Scalable verification | JWT verified locally (no DB hit for access) |
| Revocation possible | Refresh tokens stored in DB/Redis, revocable |

### Token Flow
```
1. Login → validate credentials → issue access + refresh tokens
2. API call → attach access token in Authorization: Bearer header
3. 401 response → client calls /auth/refresh with httpOnly cookie
4. Server validates refresh token → rotates it → issues new pair
5. Logout → revoke refresh token → clear cookie
```

---

## 2 · Implementation Templates

### User Model (MongoDB + Mongoose)
```typescript
import { Schema, model, type Document } from 'mongoose';
import argon2 from 'argon2';

interface IUser extends Document {
  email: string;
  password: string;
  role: 'user' | 'admin' | 'moderator';
  isVerified: boolean;
  refreshTokens: string[];
  failedLoginAttempts: number;
  lockUntil: Date | null;
  comparePassword(candidate: string): Promise<boolean>;
}

const userSchema = new Schema<IUser>(
  {
    email: {
      type: String, required: true, unique: true,
      lowercase: true, trim: true, maxlength: 255,
    },
    password: { type: String, required: true, select: false },
    role: { type: String, enum: ['user', 'admin', 'moderator'], default: 'user' },
    isVerified: { type: Boolean, default: false },
    refreshTokens: { type: [String], select: false, default: [] },
    failedLoginAttempts: { type: Number, default: 0 },
    lockUntil: { type: Date, default: null },
  },
  { timestamps: true },
);

userSchema.pre('save', async function (next) {
  if (!this.isModified('password')) return next();
  this.password = await argon2.hash(this.password, {
    type: argon2.argon2id, memoryCost: 65536, timeCost: 3, parallelism: 4,
  });
  next();
});

userSchema.methods.comparePassword = async function (candidate: string) {
  return argon2.verify(this.password, candidate);
};

export const User = model<IUser>('User', userSchema);
```

### Token Service
```typescript
import jwt from 'jsonwebtoken';
import crypto from 'crypto';

const ACCESS_SECRET = process.env.JWT_ACCESS_SECRET!;

export const tokenService = {
  generateAccessToken(userId: string, role: string): string {
    return jwt.sign({ sub: userId, role }, ACCESS_SECRET, {
      expiresIn: '15m', algorithm: 'HS256',
    });
  },

  generateRefreshToken(): string {
    return crypto.randomBytes(40).toString('hex');
  },

  verifyAccessToken(token: string) {
    return jwt.verify(token, ACCESS_SECRET) as { sub: string; role: string };
  },

  hashRefreshToken(token: string): string {
    return crypto.createHash('sha256').update(token).digest('hex');
  },
};
```

### Auth Middleware
```typescript
export function authenticate(req: Request, _res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer '))
    throw new AppError(401, 'UNAUTHENTICATED', 'Missing or invalid token');

  try {
    const payload = tokenService.verifyAccessToken(header.slice(7));
    req.user = { id: payload.sub, role: payload.role };
    next();
  } catch {
    throw new AppError(401, 'UNAUTHENTICATED', 'Token expired or invalid');
  }
}

export function authorize(...roles: string[]) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.user || !roles.includes(req.user.role))
      throw new AppError(403, 'FORBIDDEN', 'Insufficient permissions');
    next();
  };
}
```

### Auth Controller (Login + Refresh + Logout)
```typescript
const REFRESH_COOKIE = 'rid';
const REFRESH_TTL_MS = 7 * 24 * 60 * 60 * 1000;

export async function login(req: Request, res: Response) {
  const { email, password } = LoginDto.parse(req.body);
  const user = await User.findOne({ email }).select('+password +refreshTokens');

  if (!user || !(await user.comparePassword(password)))
    throw new AppError(401, 'INVALID_CREDENTIALS', 'Invalid email or password');

  const accessToken = tokenService.generateAccessToken(user.id, user.role);
  const refreshToken = tokenService.generateRefreshToken();

  user.refreshTokens = [...user.refreshTokens.slice(-4), tokenService.hashRefreshToken(refreshToken)];
  await user.save();

  res.cookie(REFRESH_COOKIE, refreshToken, {
    httpOnly: true, secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict', maxAge: REFRESH_TTL_MS, path: '/api/auth',
  });

  res.json({ data: { accessToken, user: { id: user.id, email: user.email, role: user.role } } });
}

export async function refresh(req: Request, res: Response) {
  const token = req.cookies[REFRESH_COOKIE];
  if (!token) throw new AppError(401, 'UNAUTHENTICATED', 'No refresh token');

  const hashed = tokenService.hashRefreshToken(token);
  const user = await User.findOne({ refreshTokens: hashed }).select('+refreshTokens');
  if (!user) throw new AppError(401, 'UNAUTHENTICATED', 'Invalid refresh token');

  // Rotate: remove old, add new
  user.refreshTokens = user.refreshTokens.filter((t) => t !== hashed);
  const newRefresh = tokenService.generateRefreshToken();
  user.refreshTokens.push(tokenService.hashRefreshToken(newRefresh));
  await user.save();

  res.cookie(REFRESH_COOKIE, newRefresh, {
    httpOnly: true, secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict', maxAge: REFRESH_TTL_MS, path: '/api/auth',
  });
  res.json({ data: { accessToken: tokenService.generateAccessToken(user.id, user.role) } });
}

export async function logout(req: Request, res: Response) {
  const token = req.cookies[REFRESH_COOKIE];
  if (token) {
    const hashed = tokenService.hashRefreshToken(token);
    await User.updateOne({ refreshTokens: hashed }, { $pull: { refreshTokens: hashed } });
  }
  res.clearCookie(REFRESH_COOKIE, { path: '/api/auth' });
  res.json({ data: { message: 'Logged out' } });
}
```

---

## 3 · OAuth 2.0 / Social Login

### Flow (Authorization Code + PKCE)
```
1. Client redirects → /api/auth/google
2. Server redirects → Google with state + PKCE verifier
3. Google callback → /api/auth/google/callback?code=xxx&state=yyy
4. Server exchanges code → gets user profile
5. Find or create user → issue tokens (same as local login)
```

### Implementation (Passport.js)
```typescript
passport.use(new GoogleStrategy({
  clientID: process.env.GOOGLE_CLIENT_ID!,
  clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
  callbackURL: '/api/auth/google/callback',
}, async (_at, _rt, profile, done) => {
  try {
    let user = await User.findOne({ 'oauth.googleId': profile.id });
    if (!user) {
      user = await User.create({
        email: profile.emails?.[0]?.value,
        oauth: { googleId: profile.id },
        isVerified: true,
        role: 'user',
      });
    }
    done(null, user);
  } catch (err) { done(err as Error); }
}));
```

### OAuth Checklist
```
✓ Validate state parameter to prevent CSRF
✓ Use PKCE for public clients (SPAs, mobile)
✓ Store provider ID, not provider tokens
✓ Handle account linking (same email, different provider)
✓ Set isVerified=true for OAuth users
```

---

## 4 · RBAC (Role-Based Access Control)

### Permission Model
```typescript
const PERMISSIONS = {
  user: ['read:own_profile', 'update:own_profile', 'create:post', 'read:post'],
  moderator: ['read:any_profile', 'update:any_post', 'delete:any_post', 'ban:user'],
  admin: ['*'],
} as const;

export function hasPermission(role: keyof typeof PERMISSIONS, permission: string): boolean {
  const perms = PERMISSIONS[role];
  return perms.includes('*') || perms.includes(permission);
}

export function requirePermission(permission: string) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.user || !hasPermission(req.user.role, permission))
      throw new AppError(403, 'FORBIDDEN', 'Insufficient permissions');
    next();
  };
}
```

### Resource Ownership
```typescript
export function requireOwnership(getOwnerId: (req: Request) => string) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (req.user?.role !== 'admin' && req.user?.id !== getOwnerId(req))
      throw new AppError(403, 'FORBIDDEN', 'You do not own this resource');
    next();
  };
}
```

---

## 5 · Password Security

| Algorithm | When | Config |
|---|---|---|
| Argon2id | Default (preferred) | memory: 64MB, time: 3, parallelism: 4 |
| bcrypt | Legacy compatibility | cost factor ≥ 12 |

### Password Reset Flow
```
1. POST /auth/forgot-password { email }
   → Generate crypto.randomBytes(32), hash with SHA-256, store with 1hr expiry
   → Send email with raw token in reset link
   → Always return 200 (don't reveal if email exists)

2. POST /auth/reset-password { token, newPassword }
   → Hash received token, find matching user with valid expiry
   → Update password, invalidate ALL refresh tokens
```

---

## 6 · MFA (TOTP — Google Authenticator)

```typescript
import { authenticator } from 'otplib';

export async function setupMFA(userId: string) {
  const secret = authenticator.generateSecret();
  const uri = authenticator.keyuri(userId, 'YourApp', secret);
  await User.findByIdAndUpdate(userId, { 'mfa.tempSecret': secret });
  return { qrCode: await QRCode.toDataURL(uri), secret };
}

// Login with MFA: normal login returns { requiresMFA: true, tempToken }
// POST /auth/mfa/verify { tempToken, code } → verify TOTP → issue real tokens
```

---

## 7 · Security Hardening Checklist

```
✓ HTTPS everywhere (redirect HTTP → HTTPS)
✓ Helmet.js with strict CSP
✓ CORS: explicit origin whitelist
✓ Cookie flags: httpOnly, Secure, SameSite=Strict
✓ Rate limit auth endpoints: 5 req/15min per IP+email
✓ Account lockout after 5 failed attempts (15min cooldown)
✓ Argon2id password hashing (never MD5/SHA)
✓ Refresh token rotation on every use
✓ Invalidate all tokens on password change
✓ Uniform error messages (don't reveal user existence)
✓ Log auth events — never log passwords/tokens
✓ Timing-safe comparison for token validation
```

### Required Environment Variables
```env
JWT_ACCESS_SECRET=     # min 256-bit random
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
ALLOWED_ORIGINS=       # comma-separated CORS origins
```
