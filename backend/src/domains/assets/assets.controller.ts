import {
  Body,
  Controller,
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
import { AssetInputDto, AssetQueryDto, AssetUpdateDto } from './assets.dto';
import { AssetsService } from './assets.service';

type OwnerRequest = { user?: { userId?: string } };
function owner(req: OwnerRequest): string {
  if (!req.user?.userId || !isAccountId(req.user.userId))
    throw new UnauthorizedException();
  return req.user.userId;
}

/** Authenticated inventory API; no owner input, deletion or automatic imports. */
@Auth()
@Controller('assets')
export class AssetsController {
  constructor(private readonly service: AssetsService) {}

  /** List assets belonging to the authenticated account. */
  @Get()
  @Header('Cache-Control', 'no-store')
  list(@Req() req: OwnerRequest, @Query() query: AssetQueryDto) {
    return this.service.list(owner(req), query);
  }

  /** Return a bounded complete snapshot, never a filtered page or partial export. */
  @Get('export')
  @Header('Cache-Control', 'no-store')
  exportInventory(@Req() req: OwnerRequest) {
    return this.service.exportInventory(owner(req));
  }

  /** Create one manually entered asset. */
  @Post()
  @Header('Cache-Control', 'no-store')
  create(@Req() req: OwnerRequest, @Body() input: AssetInputDto) {
    return this.service.create(owner(req), input);
  }

  /** Replace only the authenticated owner's matching version. */
  @Put(':id')
  @Header('Cache-Control', 'no-store')
  update(
    @Req() req: OwnerRequest,
    @Param('id', new ParseUUIDPipe()) id: string,
    @Body() input: AssetUpdateDto,
  ) {
    return this.service.update(owner(req), id, input);
  }
}
