# Email System — Claude Skill (Pro)

> Build production email infrastructure. Transactional emails, templates, queues, deliverability, DMARC/SPF/DKIM. Resend + BullMQ + React Email.

---

## Core Directives

1. **Queue all emails.** Never send synchronously in request handlers.
2. **Templates are code.** Version, review, and test them like any other component.
3. **Deliverability is everything.** A sent email that lands in spam is a failed email.
4. **Never expose secrets.** Don't include internal IDs, tokens, or debug info in emails.

---

## 1 · Email Service (Resend)

### Setup
```typescript
import { Resend } from 'resend';

const resend = new Resend(process.env.RESEND_API_KEY);

interface SendEmailOptions {
  to: string | string[];
  subject: string;
  html: string;
  text?: string;
  from?: string;
  replyTo?: string;
  tags?: { name: string; value: string }[];
}

export const emailService = {
  async send(options: SendEmailOptions) {
    const { data, error } = await resend.emails.send({
      from: options.from || `${env.APP_NAME} <noreply@${env.EMAIL_DOMAIN}>`,
      to: Array.isArray(options.to) ? options.to : [options.to],
      subject: options.subject,
      html: options.html,
      text: options.text,
      reply_to: options.replyTo,
      tags: options.tags,
    });

    if (error) {
      logger.error({ error, to: options.to }, 'Email send failed');
      throw new AppError(500, 'EMAIL_FAILED', 'Failed to send email');
    }

    logger.info({ emailId: data?.id, to: options.to, subject: options.subject }, 'Email sent');
    return data;
  },
};
```

---

## 2 · Email Templates (React Email)

### Setup
```bash
npm install @react-email/components react-email
```

### Welcome Email Template
```tsx
// emails/WelcomeEmail.tsx
import { Html, Head, Body, Container, Text, Button, Heading, Hr, Preview } from '@react-email/components';

interface WelcomeEmailProps {
  name: string;
  loginUrl: string;
}

export function WelcomeEmail({ name, loginUrl }: WelcomeEmailProps) {
  return (
    <Html>
      <Head />
      <Preview>Welcome to {process.env.APP_NAME}!</Preview>
      <Body style={body}>
        <Container style={container}>
          <Heading style={h1}>Welcome, {name}! 👋</Heading>
          <Text style={text}>
            Thanks for signing up. Your account is ready to go.
          </Text>
          <Button style={button} href={loginUrl}>
            Go to Dashboard
          </Button>
          <Hr style={hr} />
          <Text style={footer}>
            If you didn't create this account, you can safely ignore this email.
          </Text>
        </Container>
      </Body>
    </Html>
  );
}

const body = { backgroundColor: '#f6f9fc', fontFamily: '-apple-system, sans-serif' };
const container = { backgroundColor: '#ffffff', margin: '0 auto', padding: '40px', borderRadius: '8px', maxWidth: '560px' };
const h1 = { color: '#1a1a1a', fontSize: '24px', fontWeight: '600', margin: '0 0 16px' };
const text = { color: '#4a4a4a', fontSize: '16px', lineHeight: '26px' };
const button = { backgroundColor: '#4F46E5', borderRadius: '6px', color: '#fff', fontSize: '16px', padding: '12px 24px', textDecoration: 'none', display: 'inline-block' };
const hr = { borderColor: '#e6e6e6', margin: '32px 0' };
const footer = { color: '#8a8a8a', fontSize: '12px' };
```

### Render Template
```typescript
import { render } from '@react-email/render';
import { WelcomeEmail } from '../emails/WelcomeEmail';

export async function sendWelcomeEmail(user: { email: string; name: string }) {
  const html = await render(WelcomeEmail({ name: user.name, loginUrl: `${env.APP_URL}/login` }));

  await emailQueue.add('send-email', {
    to: user.email,
    subject: `Welcome to ${env.APP_NAME}!`,
    html,
  });
}
```

### Template Library
| Template | Trigger | Priority |
|---|---|---|
| Welcome | User signup | Normal |
| Verify Email | Signup / email change | High |
| Password Reset | Forgot password | High |
| Team Invite | Admin invites member | Normal |
| Payment Receipt | Successful payment | Normal |
| Payment Failed | Failed charge | High |
| Trial Ending | 3 days before trial expires | Normal |
| Account Deleted | User deletes account | Normal |

---

## 3 · Email Queue (BullMQ)

### Setup
```typescript
import { Queue, Worker } from 'bullmq';
import IORedis from 'ioredis';

const connection = new IORedis(env.REDIS_URL, { maxRetriesPerRequest: null });

// Queue
export const emailQueue = new Queue('emails', {
  connection,
  defaultJobOptions: {
    attempts: 3,
    backoff: { type: 'exponential', delay: 5000 },
    removeOnComplete: { count: 1000 },
    removeOnFail: { count: 5000 },
  },
});

// Worker
const emailWorker = new Worker('emails', async (job) => {
  const { to, subject, html, text } = job.data;

  await emailService.send({ to, subject, html, text });

  logger.info({ jobId: job.id, to, subject }, 'Email job completed');
}, {
  connection,
  concurrency: 5,
  limiter: { max: 10, duration: 1000 }, // max 10 emails/second
});

emailWorker.on('failed', (job, err) => {
  logger.error({ jobId: job?.id, error: err.message }, 'Email job failed');
});
```

### Delayed / Scheduled Emails
```typescript
// Send trial ending reminder 3 days before expiry
await emailQueue.add('send-email', {
  to: user.email,
  subject: 'Your trial ends in 3 days',
  html: await render(TrialEndingEmail({ name: user.name })),
}, {
  delay: trialEndsAt.getTime() - 3 * 24 * 60 * 60 * 1000 - Date.now(),
});

// Drip campaign: send series of emails
const drip = [
  { delay: 0, template: 'welcome' },
  { delay: 24 * 60 * 60 * 1000, template: 'getting-started' },
  { delay: 3 * 24 * 60 * 60 * 1000, template: 'feature-highlight' },
  { delay: 7 * 24 * 60 * 60 * 1000, template: 'feedback-request' },
];

for (const step of drip) {
  await emailQueue.add('send-email', { to: user.email, template: step.template }, { delay: step.delay });
}
```

---

## 4 · Deliverability

### DNS Records Required
```
SPF:   TXT  v=spf1 include:_spf.resend.com ~all
DKIM:  TXT  (provided by Resend/SendGrid)
DMARC: TXT  v=DMARC1; p=quarantine; rua=mailto:dmarc@yourdomain.com
MX:    MX   (for receiving replies)
```

### Deliverability Checklist
```
DNS:
✓ SPF record configured
✓ DKIM signing enabled
✓ DMARC policy set (start with p=none, then quarantine)
✓ Custom domain verified in email provider

Content:
✓ Clear From name and address
✓ Unsubscribe link in marketing emails
✓ Plain text version alongside HTML
✓ No spammy words in subject (FREE!!!, Act Now)
✓ Reasonable image-to-text ratio

Infrastructure:
✓ Dedicated sending domain (mail.yourapp.com)
✓ Warm up new domains gradually
✓ Monitor bounce rate (keep < 2%)
✓ Monitor spam complaint rate (keep < 0.1%)
✓ Remove invalid addresses after hard bounce
```

### Bounce Handling
```typescript
// Webhook from email provider
router.post('/webhooks/email', async (req, res) => {
  const { type, email } = req.body;

  switch (type) {
    case 'bounce':
      await User.updateOne({ email }, { $set: { emailBounced: true } });
      logger.warn({ email }, 'Email bounced — marking address');
      break;
    case 'complaint':
      await User.updateOne({ email }, { $set: { emailOptedOut: true } });
      logger.warn({ email }, 'Spam complaint — opting out');
      break;
  }

  res.json({ received: true });
});

// Don't send to bounced/opted-out addresses
export async function canSendTo(email: string): Promise<boolean> {
  const user = await User.findOne({ email });
  return user && !user.emailBounced && !user.emailOptedOut;
}
```

---

## 5 · Email Checklist

```
Setup:
✓ Email provider configured (Resend/SendGrid)
✓ DNS records (SPF, DKIM, DMARC)
✓ Custom sending domain verified
✓ Queue system for async sending (BullMQ)

Templates:
✓ All templates use React Email components
✓ Plain text fallback for every email
✓ Preview text set
✓ Mobile-responsive design
✓ Tested in Gmail, Outlook, Apple Mail

Operations:
✓ Retry logic (3 attempts, exponential backoff)
✓ Bounce/complaint webhook handling
✓ Send rate limiting (respect provider limits)
✓ Email logs for debugging
✓ Monitor delivery rate, open rate, bounce rate
```
