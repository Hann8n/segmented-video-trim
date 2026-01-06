# Development Workflow for Local Package Development

This guide explains how to use this package in another app while continuing to develop it separately.

## Setup

### 1. In your app (orbyt), update `package.json`:

```json
{
  "dependencies": {
    "react-native-video-trim": "file:../react-native-video-trim"
  }
}
```

### 2. Install dependencies in your app:

```bash
cd /Users/jack/orbyt
yarn install
```

### 3. Configure Metro (for Expo apps):

Create or update `metro.config.js` in your app to watch the package source:

```javascript
const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');

const projectRoot = __dirname;
const videoTrimRoot = path.resolve(__dirname, '../react-native-video-trim');

const config = getDefaultConfig(projectRoot);

config.watchFolders = [
  projectRoot,
  videoTrimRoot,
  path.resolve(videoTrimRoot, 'src'),
];

config.resolver = {
  ...config.resolver,
  nodeModulesPaths: [
    path.resolve(projectRoot, 'node_modules'),
    path.resolve(videoTrimRoot, 'node_modules'),
  ],
  extraNodeModules: {
    'react-native-video-trim': path.resolve(videoTrimRoot, 'src'),
  },
};

module.exports = config;
```

This allows Metro to watch the source files directly, so changes are picked up without rebuilding.

## Development Workflow

### Option 1: Direct Source Watching (Recommended for JS/TS changes)

With the Metro config above, Metro will watch the source files directly. This means:
- ✅ Changes to TypeScript/JavaScript files in `src/` are picked up immediately
- ✅ No rebuild needed for JS/TS changes
- ✅ Fast iteration cycle

**Workflow:**
1. Make changes to files in `src/` directory
2. Save the file
3. Metro will automatically reload your app

### Option 2: Watch Mode (For when you need built files)

If you need the built files (e.g., for testing the build output), run:

```bash
cd /Users/jack/react-native-video-trim
yarn watch
```

This will watch for changes and rebuild automatically. However, with the Metro config above, this is usually not necessary for development.

### Option 3: Manual Build

When you need to rebuild manually:

```bash
cd /Users/jack/react-native-video-trim
yarn build
```

Then restart your app's Metro bundler.

## Native Code Changes

For changes to native code (iOS/Android):

1. Make your changes in `ios/` or `android/` directories
2. Rebuild the native app:
   - **iOS**: `cd /Users/jack/orbyt && yarn ios` (or rebuild in Xcode)
   - **Android**: `cd /Users/jack/orbyt && yarn android` (or rebuild in Android Studio)

## Best Practices

1. **For JS/TS changes**: Use Option 1 (Direct Source Watching) - it's the fastest
2. **For native changes**: Rebuild the native app
3. **Before committing**: Run `yarn build` to ensure the built files are up to date
4. **Testing**: Use the `example` app in this package for isolated testing before integrating into your main app

## Troubleshooting

### Changes not appearing?

1. Clear Metro cache: `yarn start --reset-cache` (in your app)
2. Rebuild native app if you changed native code
3. Ensure Metro config is correct and watching the right directories

### Type errors?

Make sure TypeScript can find the types. The package exports types from `lib/typescript/src/index.d.ts`, so ensure your app's `tsconfig.json` includes the package.

### Native linking issues?

If you add new native dependencies or change native code:
- **iOS**: Run `cd ios && pod install` in your app
- **Android**: Usually handled automatically, but may need a clean build
