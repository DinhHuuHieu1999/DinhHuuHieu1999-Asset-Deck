import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
  type OnModuleInit,
} from '@nestjs/common';
import { AssetsRepository } from './assets.repository';
import { buildAssetExport } from './asset-export';
import type {
  AssetInputDto,
  AssetQueryDto,
  AssetUpdateDto,
} from './assets.dto';

/** Manual equipment inventory; submitted strings are inert data, never commands. */
@Injectable()
export class AssetsService implements OnModuleInit {
  constructor(private readonly repository: AssetsRepository) {}

  /** Require operator-applied schema, without running migrations. */
  async onModuleInit(): Promise<void> {
    await this.repository.ready();
  }

  private normalize(input: AssetInputDto): AssetInputDto {
    const result = {
      name: input.name.trim(),
      category: input.category.trim(),
      serial: input.serial.trim(),
      notes: input.notes.trim(),
      status: input.status,
    };
    if (
      !result.name ||
      !result.category ||
      [result.name, result.category, result.serial, result.notes].some((v) =>
        v.includes('\0'),
      )
    ) {
      throw new BadRequestException(
        'Use nonblank name/category and text without NUL characters',
      );
    }
    return result;
  }

  /** Return a bounded page, explicitly failing rather than hiding traversal limits. */
  async list(owner: string, query: AssetQueryDto) {
    const result = await this.repository.list(owner, query);
    if (result.nextOffset !== null && result.nextOffset > 100000) {
      throw new UnprocessableEntityException(
        'Pagination limit reached; list is incomplete',
      );
    }
    return result;
  }

  /** Return one owned asset, with the same missing response for foreign IDs. */
  public async findOne(owner: string, id: string) {
    const record = await this.repository.findOne(owner, id);
    if (record === null) throw new NotFoundException('Asset is unavailable');
    return record;
  }

  /** Advisory only: not a reservation or uniqueness guarantee; never blocks writes. */
  public serialDuplicate(
    owner: string,
    serial: string,
    excludeId?: string,
  ): Promise<{ duplicate: boolean }> {
    const normalized = serial.trim();
    if ([...normalized].length > 120 || normalized.includes('\0'))
      throw new BadRequestException(
        'Use a serial within 120 characters without NUL',
      );
    return this.repository.serialDuplicate(owner, normalized, excludeId);
  }

  /** Return complete owner counts independently of list filters. */
  overview(owner: string) {
    return this.repository.overview(owner);
  }

  /** Export the full owner inventory, independently of list filters and pagination. */
  async exportInventory(owner: string) {
    return buildAssetExport(await this.repository.snapshot(owner));
  }

  /** Add one manual asset. */
  create(owner: string, input: AssetInputDto) {
    return this.repository.create(owner, this.normalize(input));
  }

  /** Hide non-owner existence and reject stale updates without replacing the record. */
  async update(owner: string, id: string, input: AssetUpdateDto) {
    const record = await this.repository.update(
      owner,
      id,
      input.version,
      this.normalize(input),
    );
    if (!record)
      throw new ConflictException(
        'Asset changed or is unavailable; reload before editing',
      );
    return record;
  }
}
