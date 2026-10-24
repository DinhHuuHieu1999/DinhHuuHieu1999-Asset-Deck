import {
  BadRequestException,
  ConflictException,
  UnprocessableEntityException,
  UnauthorizedException,
  ValidationPipe,
} from '@nestjs/common';
import { AssetInputDto, AssetQueryDto, AssetUpdateDto } from './assets.dto';
import { AssetsRepository } from './assets.repository';
import { AssetsService } from './assets.service';
import { AssetsController } from './assets.controller';

const owner = '507f1f77bcf86cd799439011';
const other = '507f1f77bcf86cd799439012';
const id = '72d9a3cd-3eb1-40ea-ac3f-d549d77ff8da';
const input = {
  name: 'Router',
  category: 'network',
  serial: 'ABC',
  status: 'in_use' as const,
  notes: 'Home office',
};

describe('Asset validation boundary', () => {
  const pipe = new ValidationPipe({
    transform: true,
    whitelist: true,
    forbidNonWhitelisted: true,
  });
  function validate(value: unknown, type = AssetInputDto) {
    return pipe.transform(value, { type: 'body', metatype: type });
  }

  it('accepts bounded Unicode and optional serial/notes defaults', async () => {
    await expect(
      validate({ name: 'Thiết bị', category: 'network', status: 'stored' }),
    ).resolves.toMatchObject({ serial: '', notes: '' });
    await expect(
      validate({
        ...input,
        name: 'x'.repeat(120),
        category: 'x'.repeat(64),
        serial: 'x'.repeat(120),
        notes: 'x'.repeat(2000),
      }),
    ).resolves.toBeDefined();
  });

  it.each([
    { name: '' },
    { name: 'x'.repeat(121) },
    { category: 'x'.repeat(65) },
    { serial: 'x'.repeat(121) },
    { notes: 'x'.repeat(2001) },
    { status: 'active' },
    { name: null },
    { serial: null },
    { notes: 42 },
    { category: 'bad\0text' },
    { ownerId: other },
    { id },
    { version: 1 },
    { createdAt: 'now' },
  ])('rejects malformed or server-owned fields %j', async (patch) => {
    await expect(validate({ ...input, ...patch })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it.each([0, -1, 1.5, '1', 2147483647, null])(
    'rejects edit version %j',
    async (version) => {
      await expect(
        validate({ ...input, version }, AssetUpdateDto),
      ).rejects.toBeInstanceOf(BadRequestException);
    },
  );

  it('accepts an integer edit version and rejects unknown query controls', async () => {
    await expect(
      validate({ ...input, version: 1 }, AssetUpdateDto),
    ).resolves.toBeDefined();
    await expect(
      pipe.transform(
        { q: '%_', status: 'repair', offset: '50' },
        { type: 'query', metatype: AssetQueryDto },
      ),
    ).resolves.toMatchObject({ offset: 50, q: '%_' });
    for (const query of [
      { offset: '-1' },
      { offset: '100001' },
      { offset: 'NaN' },
      { owner },
      { status: 'active' },
      { q: ['x'] },
      { q: 'x'.repeat(121) },
      { q: '\0' },
    ]) {
      await expect(
        pipe.transform(query, { type: 'query', metatype: AssetQueryDto }),
      ).rejects.toBeInstanceOf(BadRequestException);
    }
  });
});

describe('Asset repository owner and SQL boundary', () => {
  function setup(rows: unknown[] = []) {
    const query = jest.fn().mockResolvedValue({ rows });
    return {
      query,
      repository: new AssetsRepository({ pool: { query } } as never),
    };
  }

  it('checks schema without fetching records or running DDL', async () => {
    const { query, repository } = setup();
    await repository.ready();
    expect(query).toHaveBeenCalledWith(
      expect.stringMatching(/FROM assets.assets LIMIT 0$/),
    );
    expect(query.mock.calls[0][0]).not.toMatch(/CREATE|ALTER|INSERT|UPDATE/);
  });

  it('uses literal strpos, owner binding and filtering before pagination', async () => {
    const { query, repository } = setup();
    await repository.list(owner.toUpperCase(), {
      q: "%_' OR true --",
      status: 'repair',
      offset: 50,
    });
    const [sql, values] = query.mock.calls[0];
    expect(values).toEqual([owner, 50, "%_' OR true --", 'repair']);
    expect(sql).not.toContain(values[2]);
    expect(sql).toContain('WHERE owner_id=$1');
    expect(sql).toContain('strpos(lower(serial),lower($3))');
    expect(sql).not.toMatch(/ILIKE|LIKE/);
    expect(sql).toMatch(
      /status=\$4[\s\S]*ORDER BY updated_at DESC,id DESC LIMIT 51 OFFSET \$2/,
    );
  });

  it.each([0, 1, 50, 51])(
    'returns a 50-row page with correct continuation for %i rows',
    async (count) => {
      const { repository } = setup(
        Array.from({ length: count }, (_, n) => ({ id: n })),
      );
      const page = await repository.list(owner, {
        q: '',
        status: '',
        offset: 50,
      });
      expect(page.items).toHaveLength(Math.min(count, 50));
      expect(page.nextOffset).toBe(count > 50 ? 100 : null);
    },
  );

  it('creates duplicate labels with distinct server IDs and binds each owner', async () => {
    const { query, repository } = setup([{ id }]);
    await repository.create(owner, input);
    await repository.create(other, input);
    const first = query.mock.calls[0][1],
      second = query.mock.calls[1][1];
    expect(first[0]).not.toBe(second[0]);
    expect(first.slice(1)).toEqual([
      owner,
      input.name,
      input.category,
      input.serial,
      input.status,
      input.notes,
    ]);
    expect(second[1]).toBe(other);
    expect(query.mock.calls[0][0]).not.toMatch(/ON CONFLICT/);
  });

  it('updates atomically against owner, ID and version, without leaking missing records', async () => {
    const { query, repository } = setup();
    await expect(repository.update(other, id, 3, input)).resolves.toBeNull();
    expect(query.mock.calls[0][0]).toContain(
      'WHERE owner_id=$1 AND id=$2 AND version=$3',
    );
    expect(query.mock.calls[0][0]).toContain('version=version+1');
    expect(query.mock.calls[0][1]).toEqual([
      other,
      id,
      3,
      input.name,
      input.category,
      input.serial,
      input.status,
      input.notes,
    ]);
  });

  it('rejects malformed owners before I/O and does not retry a storage error', async () => {
    const { query, repository } = setup();
    await expect(repository.create('bad', input)).rejects.toThrow(
      'invalid_asset_owner',
    );
    await expect(repository.list('bad', new AssetQueryDto())).rejects.toThrow(
      'invalid_asset_owner',
    );
    await expect(repository.update('bad', id, 1, input)).rejects.toThrow(
      'invalid_asset_owner',
    );
    expect(query).not.toHaveBeenCalled();
    query.mockRejectedValue(new Error('synthetic unavailable'));
    await expect(repository.create(owner, input)).rejects.toThrow(
      'synthetic unavailable',
    );
    expect(query).toHaveBeenCalledTimes(1);
  });
});

describe('Asset service and controller boundary', () => {
  function setup() {
    const repository = {
      ready: jest.fn().mockResolvedValue(undefined),
      list: jest.fn().mockResolvedValue({ items: [], nextOffset: null }),
      create: jest.fn().mockResolvedValue({ id, ...input }),
      update: jest.fn().mockResolvedValue({ id, ...input, version: 2 }),
    };
    const service = new AssetsService(repository as never);
    return { repository, service, controller: new AssetsController(service) };
  }

  it('trims field edges without mutating the submitted draft', async () => {
    const { repository, service } = setup();
    const draft = {
      ...input,
      name: ' Router ',
      category: ' network ',
      serial: ' ABC ',
      notes: ' Home office ',
    };
    await service.create(owner, draft);
    expect(repository.create).toHaveBeenCalledWith(owner, input);
    expect(draft.name).toBe(' Router ');
  });

  it.each([{ name: ' ' }, { category: '\n' }, { serial: 'bad\0serial' }])(
    'rejects invalid normalized input without a write %j',
    (patch) => {
      const { repository, service } = setup();
      expect(() => service.create(owner, { ...input, ...patch })).toThrow(
        BadRequestException,
      );
      expect(repository.create).not.toHaveBeenCalled();
    },
  );

  it('reports both non-owner/missing and stale edits as the same conflict', async () => {
    const { repository, service } = setup();
    repository.update.mockResolvedValue(null as never);
    const draft = { ...input, version: 1 };
    await expect(service.update(other, id, draft)).rejects.toBeInstanceOf(
      ConflictException,
    );
    expect(draft).toEqual({ ...input, version: 1 });
    expect(repository.update).toHaveBeenCalledTimes(1);
  });

  it('fails startup readiness and reports traversal truncation instead of completeness', async () => {
    const { repository, service } = setup();
    repository.ready.mockRejectedValue(new Error('schema missing'));
    await expect(service.onModuleInit()).rejects.toThrow('schema missing');
    repository.list.mockResolvedValue({
      items: [],
      nextOffset: 100050,
    } as never);
    await expect(
      service.list(owner, new AssetQueryDto()),
    ).rejects.toBeInstanceOf(UnprocessableEntityException);
  });

  it('uses the authenticated identity and rejects missing/invalid identity', async () => {
    const { repository, controller } = setup();
    await controller.create({ user: { userId: owner } }, input);
    expect(repository.create).toHaveBeenCalledWith(owner, input);
    expect(() => controller.list({}, new AssetQueryDto())).toThrow(
      UnauthorizedException,
    );
    expect(() => controller.create({ user: { userId: 'bad' } }, input)).toThrow(
      UnauthorizedException,
    );
  });
});
