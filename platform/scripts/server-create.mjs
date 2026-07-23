import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import { fileURLToPath } from 'node:url'

const platformRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const source = path.resolve(platformRoot, '..', 'backend')
const destination = path.join(platformRoot, 'server')

if (!fs.statSync(source, { throwIfNoEntry: false })?.isDirectory()) {
  throw new Error(`Missing fixed monorepo component: ${source}`)
}
if (fs.existsSync(destination)) {
  throw new Error(`Destination already exists: ${destination}`)
}

fs.cpSync(source, destination, {
  recursive: true,
  filter: (entry) => !['.git', '.gitignore'].includes(path.basename(entry)),
})
fs.writeFileSync(
  path.join(destination, '.env'),
  `PALLASTRADE_GEMS_PATH=..\nSECRET_KEY_BASE=${crypto.randomBytes(64).toString('hex')}\n`,
)
console.log(`Created ${destination} from backend/.`)
