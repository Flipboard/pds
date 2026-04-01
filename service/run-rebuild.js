const { AppContext, readEnv, envToCfg, envToSecrets, scripts } = require('@atproto/pds')
async function main() {
  const did = process.argv[2]
  if (!did) throw new Error('Usage: node run-rebuild.js <did>')
  const env = readEnv()
  console.log(`Running updates on ${env.hostname}`);
  const ctx = await AppContext.fromConfig(envToCfg(env), envToSecrets(env))
  await scripts['rebuild-repo'](ctx, did, false)
  console.log('DONE')
}
main().catch((err) => {
  console.error(err)
  process.exit(1)
})