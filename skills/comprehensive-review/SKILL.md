---
name: comprehensive-review
description: Use after implementing features - 7-criteria code review covering blindspots, clarity, maintainability, security, performance, documentation, and style
---

# Comprehensive Review

## Overview

Review code against 7 criteria before considering it complete.

**Core principle:** Self-review catches issues before they reach others.

**Announce at start:** "I'm performing a comprehensive code review."

## The 7 Criteria

### 1. Blindspots

**Question:** What am I missing?

| Check | Ask Yourself |
|-------|--------------|
| Edge cases | What happens at boundaries? Empty input? Max values? |
| Error paths | What if external services fail? Network issues? |
| Concurrency | Multiple users/threads? Race conditions? |
| State | What if called in wrong order? Invalid state? |
| Dependencies | What if dependency behavior changes? |

```typescript
// Blindspot example: What if items is empty?
function calculateAverage(items: number[]): number {
  return items.reduce((a, b) => a + b, 0) / items.length;
  // Blindspot: Division by zero when items is empty!
}

// Fixed
function calculateAverage(items: number[]): number {
  if (items.length === 0) {
    throw new Error('Cannot calculate average of empty array');
  }
  return items.reduce((a, b) => a + b, 0) / items.length;
}
```

### 2. Clarity/Consistency

**Question:** Will someone else understand this?

| Check | Ask Yourself |
|-------|--------------|
| Names | Do names describe what things do/are? |
| Structure | Is code organized logically? |
| Complexity | Can this be simplified? |
| Patterns | Does this match existing patterns? |
| Surprises | Would anything surprise a reader? |

```typescript
// Unclear
function proc(d: any, f: boolean): any {
  return f ? d.map((x: any) => x * 2) : d;
}

// Clear
function doubleValuesIfEnabled(
  values: number[],
  shouldDouble: boolean
): number[] {
  if (!shouldDouble) {
    return values;
  }
  return values.map(value => value * 2);
}
```

### 3. Maintainability

**Question:** Can this be changed safely?

| Check | Ask Yourself |
|-------|--------------|
| Coupling | Is this tightly bound to other code? |
| Cohesion | Does this do one thing well? |
| Duplication | Is logic repeated anywhere? |
| Tests | Do tests cover this adequately? |
| Extensibility | Can new features be added easily? |

```typescript
// Hard to maintain: tightly coupled
class OrderService {
  async createOrder(data: OrderData): Promise<Order> {
    const user = await db.query('SELECT * FROM users WHERE id = ?', [data.userId]);
    const inventory = await db.query('SELECT * FROM inventory WHERE id = ?', [data.productId]);
    await emailService.send(user.email, 'Order Created', orderTemplate(data));
    await db.query('INSERT INTO orders ...', [...]);
    return order;
  }
}

// Maintainable: loosely coupled
class OrderService {
  constructor(
    private userRepository: UserRepository,
    private inventoryRepository: InventoryRepository,
    private notificationService: NotificationService,
    private orderRepository: OrderRepository
  ) {}

  async createOrder(data: OrderData): Promise<Order> {
    const user = await this.userRepository.findById(data.userId);
    const inventory = await this.inventoryRepository.check(data.productId);
    const order = await this.orderRepository.create(data);
    await this.notificationService.orderCreated(user, order);
    return order;
  }
}
```

### 4. Security Risks

**Question:** Can this be exploited?

| Check | Ask Yourself |
|-------|--------------|
| Input validation | Is all input validated and sanitized? |
| Authentication | Is access properly controlled? |
| Authorization | Are permissions checked? |
| Data exposure | Is sensitive data protected? |
| Injection | SQL, XSS, command injection possible? |
| Dependencies | Are dependencies secure and updated? |

```typescript
// Security risk: SQL injection
async function findUser(username: string): Promise<User> {
  return db.query(`SELECT * FROM users WHERE username = '${username}'`);
}

// Secure: parameterized query
async function findUser(username: string): Promise<User> {
  return db.query('SELECT * FROM users WHERE username = ?', [username]);
}

// Security risk: XSS
function renderComment(comment: string): string {
  return `<div>${comment}</div>`;
}

// Secure: escaped output
function renderComment(comment: string): string {
  return `<div>${escapeHtml(comment)}</div>`;
}
```

### 5. Performance Implications

**Question:** Will this scale?

| Check | Ask Yourself |
|-------|--------------|
| Algorithms | Is complexity appropriate? O(n²) when O(n) possible? |
| Database | N+1 queries? Missing indexes? Full table scans? |
| Memory | Large objects in memory? Memory leaks? |
| Network | Unnecessary requests? Large payloads? |
| Caching | Should results be cached? |

```typescript
// Performance issue: N+1 queries
async function getOrdersWithUsers(orderIds: string[]): Promise<OrderWithUser[]> {
  const orders = await orderRepository.findByIds(orderIds);
  // N+1: One query per order!
  return Promise.all(orders.map(async order => ({
    ...order,
    user: await userRepository.findById(order.userId),
  })));
}

// Fixed: Batch query
async function getOrdersWithUsers(orderIds: string[]): Promise<OrderWithUser[]> {
  const orders = await orderRepository.findByIds(orderIds);
  const userIds = [...new Set(orders.map(o => o.userId))];
  const users = await userRepository.findByIds(userIds);
  const userMap = new Map(users.map(u => [u.id, u]));

  return orders.map(order => ({
    ...order,
    user: userMap.get(order.userId)!,
  }));
}
```

### 6. Documentation

**Question:** Is this documented adequately?

| Check | Ask Yourself |
|-------|--------------|
| Public APIs | Are all public functions documented? |
| Parameters | Are parameter types and purposes clear? |
| Returns | Is return value documented? |
| Errors | Are thrown errors documented? |
| Examples | Are complex usages demonstrated? |
| Why | Are non-obvious decisions explained? |

See `inline-documentation` skill for documentation standards.

### 7. Standards and Style

**Question:** Does this follow project conventions?

| Check | Ask Yourself |
|-------|--------------|
| Naming | Follows project naming conventions? |
| Formatting | Matches project formatting? |
| Patterns | Uses established patterns? |
| Types | Fully typed (no `any`)? |
| Language | Uses inclusive language? |
| IPv6-first | Network code uses IPv6 by default? IPv4 only for documented legacy? |
| Linting | Passes all linters? |

See `style-guide-adherence`, `strict-typing`, `inclusive-language`, `ipv6-first` skills.

## Review Process

### Step 1: Prepare

```bash
# Get list of changed files
git diff --name-only HEAD~1

# Get full diff
git diff HEAD~1
```

### Step 2: Review Each Criterion

For each of the 7 criteria:

1. Review all changed code
2. Note any issues found
3. Determine severity (Critical/Major/Minor)

### Step 3: Document Findings

```markdown
## Code Review Findings

### 1. Blindspots
- [ ] **Critical**: No handling for empty array in `calculateAverage()`
- [ ] **Minor**: Missing null check in `formatUser()`

### 2. Clarity/Consistency
- [ ] **Major**: Variable `x` should have descriptive name
- [ ] **Minor**: Inconsistent spacing in `config.ts`

### 3. Maintainability
- [x] No issues found

### 4. Security Risks
- [ ] **Critical**: SQL injection possible in `findUser()`

### 5. Performance Implications
- [ ] **Major**: N+1 query in `getOrdersWithUsers()`

### 6. Documentation
- [ ] **Minor**: Missing JSDoc on `processOrder()`

### 7. Standards and Style
- [x] Passes all checks
```

### Step 4: Address All Findings

Use `apply-all-findings` skill to address every issue.

## Severity Levels

| Severity | Description | Action |
|----------|-------------|--------|
| **Critical** | Security issue, data loss, crash | Must fix before merge |
| **Major** | Significant bug, performance issue | Must fix before merge |
| **Minor** | Style, clarity, small improvement | Should fix before merge |

## Checklist

Complete for every code review:

- [ ] Blindspots: Edge cases, errors, concurrency checked
- [ ] Clarity: Names, structure, complexity reviewed
- [ ] Maintainability: Coupling, cohesion, tests evaluated
- [ ] Security: Input, auth, injection, exposure checked
- [ ] Performance: Algorithms, queries, memory reviewed
- [ ] Documentation: Public APIs documented
- [ ] Style: Conventions followed
- [ ] All findings documented
- [ ] All findings addressed

## Integration

This skill is called by:
- `issue-driven-development` - Step 9

This skill uses:
- `review-scope` - Determine review breadth
- `apply-all-findings` - Address issues

This skill references:
- `inline-documentation` - Documentation standards
- `strict-typing` - Type requirements
- `style-guide-adherence` - Style requirements
- `inclusive-language` - Language requirements
- `ipv6-first` - Network code requirements (IPv6 primary, IPv4 legacy)
