import { useEffect, useState } from 'react';
import AppNewArch from './App.NewArch';
import AppOldArch from './App.OldArch';

export default function App() {
  const [useNewArch, setUseNewArch] = useState<boolean | null>(null);

  useEffect(() => {
    // Detect if new architecture is available
    const hasNewArch = !!(global as any)?.nativeFabricUIManager;
    console.log('Architecture detection:', { hasNewArch });
    setUseNewArch(hasNewArch);
  }, []);

  // Show nothing while detecting architecture
  if (useNewArch === null) {
    return null;
  }

  // Use new architecture if available, otherwise fall back to old
  return useNewArch ? <AppNewArch /> : <AppOldArch />;
}
