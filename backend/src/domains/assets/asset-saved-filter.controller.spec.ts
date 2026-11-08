import { AssetSavedFilterController } from './asset-saved-filter.controller';
import type { AssetSavedFilterRepository } from './asset-saved-filter.repository';
const account = '507f1f77bcf86cd799439011';
const req = { user: { userId: account } };
const query = {
  q: '%_',
  status: '',
  category: '',
  sort: 'updated_desc',
  locationMode: 'all',
  location: '',
  warranty: 'all',
  asOf: '',
  checkMode: 'all',
  checkBefore: '',
  checkOnOrAfter: '',
};
function setup() {
  const repository = { list: jest.fn(), create: jest.fn(), change: jest.fn() };
  return {
    repository,
    controller: new AssetSavedFilterController(
      repository as unknown as AssetSavedFilterRepository,
    ),
  };
}
describe('saved filter controller validation', () => {
  it('takes owner from auth only', async () => {
    const f = setup();
    await f.controller.create(
      req,
      {},
      { name: 'View', schemaVersion: 1, query },
    );
    expect(f.repository.create).toHaveBeenCalledWith(account, 'View', query);
    await expect(f.controller.list({}, {})).rejects.toThrow();
    await expect(f.controller.list(req, { owner: account })).rejects.toThrow();
  });
  it.each([
    { name: 'View', schemaVersion: 2, query },
    { name: 'View', schemaVersion: 1, query, owner: account },
  ])('rejects extra fields and unsupported schema', async (value) => {
    const f = setup();
    await expect(f.controller.create(req, {}, value)).rejects.toThrow();
    expect(f.repository.create).not.toHaveBeenCalled();
  });
  it('validates version and deletion body before repository calls', async () => {
    const f = setup();
    await expect(
      f.controller.remove(req, {}, 'id', { version: 0 }),
    ).rejects.toThrow();
    await expect(
      f.controller.remove(req, {}, 'id', { version: 1, owner: account }),
    ).rejects.toThrow();
    expect(f.repository.change).not.toHaveBeenCalled();
    await f.controller.remove(req, {}, 'id', { version: 2 });
    expect(f.repository.change).toHaveBeenCalledWith(account, 'id', 2);
  });
});
