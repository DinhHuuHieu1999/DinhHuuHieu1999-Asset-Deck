import { NestFactory } from '@nestjs/core';
import { bootstrap } from './main';

jest.mock('./app/modules/app.module', () => ({ AppModule: class {} }));
jest.mock('./app/config/env-files', () => ({ loadEnvFiles: jest.fn() }));
jest.mock('./app/config/startup.config', () => ({
  validateStartup: () => 8180,
}));

describe('bootstrap resource ownership without a real listener', () => {
  const app = {
    set: jest.fn(),
    use: jest.fn(),
    setGlobalPrefix: jest.fn(),
    useGlobalPipes: jest.fn(),
    enableShutdownHooks: jest.fn(),
    listen: jest.fn(),
    close: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
    app.listen.mockResolvedValue(undefined);
    app.close.mockResolvedValue(undefined);
    jest.spyOn(NestFactory, 'create').mockResolvedValue(app as never);
  });
  afterEach(() => jest.restoreAllMocks());

  it('keeps successful application running on loopback', async () => {
    await bootstrap();
    expect(app.listen).toHaveBeenCalledWith(8180, '127.0.0.1');
    expect(app.close).not.toHaveBeenCalled();
  });

  it('closes the created app on initialization/listen failure', async () => {
    const failure = new Error('synthetic startup failure');
    app.listen.mockRejectedValue(failure);
    await expect(bootstrap()).rejects.toBe(failure);
    expect(app.close).toHaveBeenCalledTimes(1);
  });

  it('retains the original failure if cleanup also fails', async () => {
    const failure = new Error('synthetic startup failure');
    app.listen.mockRejectedValue(failure);
    app.close.mockRejectedValue(new Error('synthetic cleanup failure'));
    await expect(bootstrap()).rejects.toBe(failure);
    expect(app.close).toHaveBeenCalledTimes(1);
  });

  it('does not attempt to close an application that was never returned', async () => {
    const failure = new Error('synthetic factory failure');
    jest.spyOn(NestFactory, 'create').mockRejectedValue(failure);
    await expect(bootstrap()).rejects.toBe(failure);
    expect(app.close).not.toHaveBeenCalled();
  });
});
