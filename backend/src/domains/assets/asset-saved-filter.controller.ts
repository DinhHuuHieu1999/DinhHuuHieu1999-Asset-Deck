import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Header,
  Param,
  ParseUUIDPipe,
  Post,
  Put,
  Query,
  Req,
  UnauthorizedException,
} from '@nestjs/common';
import { Auth } from '../../shared/decorators/auth.decorator';
import { isAccountId } from '../auth/account.repository';
import { isAssetCheckEnabled } from './asset-check';
import { isAssetDatesEnabled } from './asset-dates.config';
import { isAssetLocationEnabled } from './asset-location.config';
import {
  assertSavedFilterCapabilities,
  validateSavedFilterName,
  validateSavedFilterQuery,
} from './asset-saved-filter';
import { AssetSavedFilterRepository } from './asset-saved-filter.repository';

type Request = { user?: { userId?: string } };
function owner(req: Request, query: Record<string, unknown>): string {
  if (!req.user?.userId || !isAccountId(req.user.userId))
    throw new UnauthorizedException();
  if (Object.keys(query).length)
    throw new BadRequestException(
      'Saved filters do not accept query parameters',
    );
  return req.user.userId;
}
function body(value: unknown, update: boolean, deletion = false) {
  const invalid = (): never => {
    throw new BadRequestException('Invalid saved filter input');
  };
  if (
    !value ||
    typeof value !== 'object' ||
    Array.isArray(value) ||
    ![Object.prototype, null].includes(Object.getPrototypeOf(value))
  )
    return invalid();
  const input = value as Record<string, unknown>;
  const keys = deletion
    ? ['version']
    : update
      ? ['name', 'query', 'schemaVersion', 'version']
      : ['name', 'query', 'schemaVersion'];
  if (
    Object.keys(input).length !== keys.length ||
    !keys.every((key) => Object.hasOwn(input, key))
  )
    return invalid();
  if (
    update &&
    (typeof input.version !== 'number' ||
      !Number.isInteger(input.version) ||
      input.version < 1 ||
      input.version > (deletion ? 2147483647 : 2147483646))
  )
    return invalid();
  if (deletion) return { version: input.version as number };
  if (input.schemaVersion !== 1) return invalid();
  const query = validateSavedFilterQuery(input.query);
  assertSavedFilterCapabilities(query, {
    location: isAssetLocationEnabled(),
    warranty: isAssetDatesEnabled(),
    check: isAssetCheckEnabled(),
  });
  return {
    name: validateSavedFilterName(input.name),
    query,
    version: input.version as number,
  };
}

/** Account-owned query definitions; never writes inventory or accepts owner input. */
@Auth()
@Controller('inventory-saved-filters')
export class AssetSavedFilterController {
  constructor(private readonly repository: AssetSavedFilterRepository) {}

  /** List owned definitions without applying them to inventory. */
  @Get()
  @Header('Cache-Control', 'no-store')
  async list(@Req() req: Request, @Query() query: Record<string, unknown>) {
    return { items: await this.repository.list(owner(req, query)) };
  }

  /** Explicitly save a validated query under the authenticated owner. */
  @Post()
  @Header('Cache-Control', 'no-store')
  async create(
    @Req() req: Request,
    @Query() query: Record<string, unknown>,
    @Body() value: unknown,
  ) {
    const account = owner(req, query);
    const checked = body(value, false);
    return this.repository.create(account, checked.name, checked.query);
  }

  /** Replace only the version actually reviewed by this owner. */
  @Put(':id')
  @Header('Cache-Control', 'no-store')
  async update(
    @Req() req: Request,
    @Query() query: Record<string, unknown>,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Body() value: unknown,
  ) {
    const account = owner(req, query);
    const checked = body(value, true);
    return this.repository.change(account, id, checked.version, {
      name: checked.name,
      query: checked.query,
    });
  }

  /** Delete a saved definition only, never equipment or active inventory state. */
  @Delete(':id')
  @Header('Cache-Control', 'no-store')
  async remove(
    @Req() req: Request,
    @Query() query: Record<string, unknown>,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Body() value: unknown,
  ) {
    const account = owner(req, query);
    const checked = body(value, true, true);
    return this.repository.change(account, id, checked.version);
  }
}
