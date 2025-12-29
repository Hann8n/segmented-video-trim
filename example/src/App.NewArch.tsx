import {
  StyleSheet,
  View,
  Text,
  TouchableOpacity,
  ScrollView,
  Alert,
  Platform,
  SafeAreaView,
  type EventSubscription,
} from 'react-native';
import NativeVideoTrim, {
  showEditor,
  isValidFile,
  trim,
  type Spec,
} from 'react-native-video-trim';
import { launchImageLibrary } from 'react-native-image-picker';
import { useEffect, useRef, useState } from 'react';
import { SegmentManager, type Segment } from './utils/SegmentManager';

// Duration options in seconds
const DURATION_OPTIONS = [
  { value: 6, label: '6s' },
  { value: 16, label: '16s' },
  { value: 60, label: '60s' },
  { value: 180, label: '180s' },
] as const;

export default function App() {
  const [maxDuration, setMaxDuration] = useState(16);
  const [segments, setSegments] = useState<Segment[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isTrimming, setIsTrimming] = useState(false);
  const segmentManagerRef = useRef<SegmentManager | null>(null);
  const listenerSubscription = useRef<Record<string, EventSubscription>>({});

  // Initialize segment manager
  useEffect(() => {
    if (!segmentManagerRef.current) {
      segmentManagerRef.current = new SegmentManager(maxDuration);
    }
  }, [maxDuration]);

  // Update max duration when selected duration changes
  useEffect(() => {
    if (segmentManagerRef.current) {
      segmentManagerRef.current.setMaxDuration(maxDuration);
      // Update segments state to trigger UI refresh
      setSegments(segmentManagerRef.current.getSegments());
    }
  }, [maxDuration]);

  // Handle trimmed video from gallery
  const handleTrimmingComplete = ({
    outputPath,
    startTime,
    endTime,
  }: {
    outputPath: string;
    startTime: number;
    endTime: number;
  }) => {
    if (!segmentManagerRef.current) return;

    // Calculate trimmed duration (all times in milliseconds, convert to seconds)
    // Use precise values (no rounding) for validation - display is rounded separately
    const trimmedDurationSeconds = (endTime - startTime) / 1000;

    // Validate trimmed duration doesn't exceed available time
    // Round both to milliseconds (0.001s) for comparison to handle floating point precision
    // All actual values remain precise - rounding only for this comparison
    const availableTime = segmentManagerRef.current.getAvailableTime();
    const trimmedRounded = Math.round(trimmedDurationSeconds * 1000) / 1000;
    const availableRounded = Math.round(availableTime * 1000) / 1000;
    if (trimmedRounded > availableRounded) {
      Alert.alert(
        'Error',
        `Trimmed video (${trimmedDurationSeconds}s) exceeds available time (${availableTime}s). Please trim to a shorter duration.`
      );
      setIsLoading(false);
      return;
    }

    // Add segment
    const videoUri = outputPath.startsWith('file://')
      ? outputPath
      : `file://${outputPath}`;
    const newSegment: Segment = {
      duration: trimmedDurationSeconds,
      video: { uri: videoUri },
      sourceType: 'gallery',
    };

    if (!segmentManagerRef.current.addSegment(newSegment)) {
      Alert.alert(
        'Error',
        'Adding this video would exceed the maximum duration'
      );
      setIsLoading(false);
      return;
    }

    // Update UI
    setSegments(segmentManagerRef.current.getSegments());
    setIsLoading(false);
    console.log('Segment added:', {
      duration: trimmedDurationSeconds,
      totalDuration: segmentManagerRef.current.getTotalDuration(),
      availableTime: segmentManagerRef.current.getAvailableTime(),
    });
  };

  // Set up event listeners
  useEffect(() => {
    console.log('Setting up event listeners (New Architecture)');

    listenerSubscription.current.onLoad = (NativeVideoTrim as Spec).onLoad(
      ({ duration }) => console.log('onLoad', duration)
    );

    listenerSubscription.current.onStartTrimming = (
      NativeVideoTrim as Spec
    ).onStartTrimming(() => console.log('onStartTrimming'));

    listenerSubscription.current.onCancelTrimming = (
      NativeVideoTrim as Spec
    ).onCancelTrimming(() => console.log('onCancelTrimming'));

    listenerSubscription.current.onCancel = (NativeVideoTrim as Spec).onCancel(
      () => console.log('onCancel')
    );

    listenerSubscription.current.onHide = (NativeVideoTrim as Spec).onHide(() =>
      console.log('onHide')
    );

    listenerSubscription.current.onShow = (NativeVideoTrim as Spec).onShow(() =>
      console.log('onShow')
    );

    listenerSubscription.current.onFinishTrimming = (
      NativeVideoTrim as Spec
    ).onFinishTrimming(handleTrimmingComplete);

    listenerSubscription.current.onLog = (NativeVideoTrim as Spec).onLog(
      ({ level, message, sessionId }) =>
        console.log(
          'onLog',
          `level: ${level}, message: ${message}, sessionId: ${sessionId}`
        )
    );

    listenerSubscription.current.onStatistics = (
      NativeVideoTrim as Spec
    ).onStatistics(
      ({
        sessionId,
        videoFrameNumber,
        videoFps,
        videoQuality,
        size,
        time,
        bitrate,
        speed,
      }) =>
        console.log(
          'onStatistics',
          `sessionId: ${sessionId}, videoFrameNumber: ${videoFrameNumber}, videoFps: ${videoFps}, videoQuality: ${videoQuality}, size: ${size}, time: ${time}, bitrate: ${bitrate}, speed: ${speed}`
        )
    );

    listenerSubscription.current.onError = (NativeVideoTrim as Spec).onError(
      ({ message, errorCode }) => {
        console.log('onError', `message: ${message}, errorCode: ${errorCode}`);
        Alert.alert('Error', message || 'Failed to trim video');
        setIsLoading(false);
      }
    );

    return () => {
      listenerSubscription.current.onLoad?.remove();
      listenerSubscription.current.onStartTrimming?.remove();
      listenerSubscription.current.onCancelTrimming?.remove();
      listenerSubscription.current.onCancel?.remove();
      listenerSubscription.current.onHide?.remove();
      listenerSubscription.current.onShow?.remove();
      listenerSubscription.current.onFinishTrimming?.remove();
      listenerSubscription.current.onLog?.remove();
      listenerSubscription.current.onStatistics?.remove();
      listenerSubscription.current.onError?.remove();
      listenerSubscription.current = {};
    };
  }, []);

  const totalDuration = segmentManagerRef.current?.getTotalDuration() ?? 0;
  const availableTime = segmentManagerRef.current?.getAvailableTime() ?? 0;
  const progressPercentage =
    maxDuration > 0 ? (totalDuration / maxDuration) * 100 : 0;

  const pickFromGallery = async () => {
    try {
      setIsLoading(true);

      const result = await launchImageLibrary({
        mediaType: 'video',
        includeExtra: true,
        assetRepresentationMode: 'current',
      });

      if (!result.assets || result.assets.length === 0) {
        setIsLoading(false);
        return;
      }

      const videoUri = result.assets[0]?.uri || '';

      // Validate file
      const validationResult = await isValidFile(videoUri);
      if (!validationResult.isValid) {
        Alert.alert(
          'Invalid Video',
          'The selected video file cannot be accessed.'
        );
        setIsLoading(false);
        return;
      }

      // Check if there's available time
      if (availableTime <= 0) {
        Alert.alert('Error', 'No time remaining. Maximum duration reached.');
        setIsLoading(false);
        return;
      }

      // Show editor with dynamic maxDuration constraint
      // Pass precise value (no rounding) - only display rounds in trimmer UI
      const maxDurationSeconds = availableTime;

      showEditor(videoUri, {
        maxDuration: maxDurationSeconds,
        saveToPhoto: false,
        openShareSheetOnFinish: false,
        removeAfterSavedToPhoto: false,
        cancelButtonText: 'Cancel',
        saveButtonText: 'Done',
        trimmerColor: '#4528ea',
        enableCancelTrimming: true,
        closeWhenFinish: true,
        autoplay: true,
        fullScreenModalIOS: true,
      });
    } catch (error) {
      console.error('Error opening trimmer:', error);
      Alert.alert('Error', 'Failed to open video trimmer');
      setIsLoading(false);
    }
  };

  const deleteLastSegment = () => {
    if (!segmentManagerRef.current) return;

    if (segmentManagerRef.current.removeLastSegment()) {
      setSegments(segmentManagerRef.current.getSegments());
      console.log('Last segment deleted');
    }
  };

  const clearAllSegments = () => {
    if (!segmentManagerRef.current) return;

    segmentManagerRef.current.clear();
    setSegments([]);
    console.log('All segments cleared');
  };

  const getProgressBarColor = () => {
    if (progressPercentage >= 100) return '#ef4444'; // red
    if (progressPercentage >= 80) return '#f59e0b'; // yellow
    return '#10b981'; // green
  };

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
      >
        {/* Header Section */}
        <View style={styles.header}>
          <Text style={styles.title}>Video Segment Trimmer</Text>
          <Text style={styles.subtitle}>
            Test multiple clips with dynamic max duration
          </Text>
        </View>

        {/* Max Duration Selector */}
        <View style={styles.durationSelector}>
          <Text style={styles.label}>Max Duration:</Text>
          <View style={styles.durationButtons}>
            {DURATION_OPTIONS.map((option) => (
              <TouchableOpacity
                key={option.value}
                style={[
                  styles.durationButton,
                  maxDuration === option.value && styles.durationButtonActive,
                  segmentManagerRef.current?.hasSegments() &&
                    styles.durationButtonDisabled,
                ]}
                onPress={() => {
                  if (!segmentManagerRef.current?.hasSegments()) {
                    setMaxDuration(option.value);
                  }
                }}
                disabled={segmentManagerRef.current?.hasSegments() ?? false}
              >
                <Text
                  style={[
                    styles.durationButtonText,
                    maxDuration === option.value &&
                      styles.durationButtonTextActive,
                    segmentManagerRef.current?.hasSegments() &&
                      maxDuration !== option.value &&
                      styles.durationButtonTextDisabled,
                  ]}
                >
                  {option.label}
                </Text>
              </TouchableOpacity>
            ))}
          </View>
        </View>

        {/* Stats Display */}
        <View style={styles.statsContainer}>
          <View style={styles.statItem}>
            <Text style={styles.statLabel}>Max:</Text>
            <Text style={styles.statValue}>{maxDuration}s</Text>
          </View>
          <View style={styles.statItem}>
            <Text style={styles.statLabel}>Used:</Text>
            <Text style={styles.statValue}>{totalDuration}s</Text>
          </View>
          <View style={styles.statItem}>
            <Text style={styles.statLabel}>Available:</Text>
            <Text
              style={[
                styles.statValue,
                availableTime <= 0 && styles.statValueWarning,
              ]}
            >
              {availableTime}s
            </Text>
          </View>
        </View>

        {/* Progress Bar */}
        <View style={styles.progressBarContainer}>
          <View
            style={[
              styles.progressBarFill,
              {
                width: `${Math.min(progressPercentage, 100)}%`,
                backgroundColor: getProgressBarColor(),
              },
            ]}
          />
        </View>

        {/* Segments List */}
        <View style={styles.segmentsContainer}>
          <Text style={styles.sectionTitle}>Segments ({segments.length})</Text>
          {segments.length === 0 ? (
            <View style={styles.emptyState}>
              <Text style={styles.emptyStateText}>
                No segments yet. Add a video segment to get started.
              </Text>
            </View>
          ) : (
            <View style={styles.segmentsList}>
              {segments.map((segment, index) => (
                <View key={index} style={styles.segmentCard}>
                  <View style={styles.segmentInfo}>
                    <Text style={styles.segmentNumber}>
                      Segment {index + 1}
                    </Text>
                    <Text style={styles.segmentDuration}>
                      {segment.duration}s
                    </Text>
                    {segment.sourceType && (
                      <Text style={styles.segmentSource}>
                        ({segment.sourceType})
                      </Text>
                    )}
                  </View>
                  <Text style={styles.segmentPath} numberOfLines={1}>
                    {segment.video.uri}
                  </Text>
                </View>
              ))}
            </View>
          )}
        </View>

        {/* Action Buttons */}
        <View style={styles.actionsContainer}>
          <TouchableOpacity
            style={[
              styles.actionButton,
              styles.primaryButton,
              (availableTime <= 0 || isLoading) && styles.buttonDisabled,
            ]}
            onPress={pickFromGallery}
            disabled={availableTime <= 0 || isLoading}
          >
            <Text style={styles.actionButtonText}>
              {isLoading ? 'Loading...' : 'Add Video Segment'}
            </Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={[
              styles.actionButton,
              styles.secondaryButton,
              segments.length === 0 && styles.buttonDisabled,
            ]}
            onPress={deleteLastSegment}
            disabled={segments.length === 0}
          >
            <Text style={styles.actionButtonText}>Delete Last Segment</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={[
              styles.actionButton,
              styles.secondaryButton,
              segments.length === 0 && styles.buttonDisabled,
            ]}
            onPress={clearAllSegments}
            disabled={segments.length === 0}
          >
            <Text style={styles.actionButtonText}>Clear All</Text>
          </TouchableOpacity>

          {/* Keep original trim API test button */}
          <TouchableOpacity
            style={[styles.actionButton, styles.testButton]}
            onPress={async () => {
              const url =
                'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';

              setIsTrimming(true);
              trim(url, {
                startTime: 0,
                endTime: 15000,
                saveToPhoto: true,
              })
                .then((res) => {
                  console.log('Trimmed file:', res);
                })
                .catch((error) => {
                  console.error('Error trimming file:', error);
                })
                .finally(() => {
                  setIsTrimming(false);
                });
            }}
          >
            <Text style={styles.actionButtonText}>
              {isTrimming ? 'Trimming...' : 'Test Trim API'}
            </Text>
          </TouchableOpacity>
        </View>

        {/* Debug Info */}
        <View style={styles.debugContainer}>
          <Text style={styles.debugTitle}>Debug Info</Text>
          <Text style={styles.debugText}>Total Duration: {totalDuration}s</Text>
          <Text style={styles.debugText}>Available Time: {availableTime}s</Text>
          <Text style={styles.debugText}>Progress: {progressPercentage}%</Text>
          <Text style={styles.debugText}>Segment Count: {segments.length}</Text>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000000',
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: 16,
    paddingBottom: 32,
  },
  header: {
    marginBottom: 24,
    alignItems: 'center',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#ffffff',
    marginBottom: 4,
  },
  subtitle: {
    fontSize: 14,
    color: '#9ca3af',
  },
  durationSelector: {
    marginBottom: 16,
  },
  label: {
    fontSize: 16,
    fontWeight: '600',
    color: '#ffffff',
    marginBottom: 8,
  },
  durationButtons: {
    flexDirection: 'row',
    gap: 8,
  },
  durationButton: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 8,
    backgroundColor: '#1a1a1a',
    borderWidth: 2,
    borderColor: '#2a2a2a',
  },
  durationButtonActive: {
    backgroundColor: '#6366f1',
    borderColor: '#6366f1',
  },
  durationButtonDisabled: {
    opacity: 0.5,
  },
  durationButtonText: {
    fontSize: 14,
    fontWeight: '600',
    color: '#ffffff',
  },
  durationButtonTextActive: {
    color: '#ffffff',
  },
  durationButtonTextDisabled: {
    color: '#6b7280',
  },
  statsContainer: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    backgroundColor: '#1a1a1a',
    padding: 16,
    borderRadius: 12,
    marginBottom: 16,
    borderWidth: 1,
    borderColor: '#2a2a2a',
  },
  statItem: {
    alignItems: 'center',
  },
  statLabel: {
    fontSize: 12,
    color: '#9ca3af',
    marginBottom: 4,
  },
  statValue: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#ffffff',
  },
  statValueWarning: {
    color: '#ef4444',
  },
  progressBarContainer: {
    height: 8,
    backgroundColor: '#1a1a1a',
    borderRadius: 4,
    overflow: 'hidden',
    marginBottom: 24,
  },
  progressBarFill: {
    height: '100%',
    borderRadius: 4,
  },
  segmentsContainer: {
    marginBottom: 24,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#ffffff',
    marginBottom: 12,
  },
  emptyState: {
    backgroundColor: '#1a1a1a',
    padding: 24,
    borderRadius: 12,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: '#2a2a2a',
  },
  emptyStateText: {
    fontSize: 14,
    color: '#9ca3af',
    textAlign: 'center',
  },
  segmentsList: {
    gap: 8,
  },
  segmentCard: {
    backgroundColor: '#1a1a1a',
    padding: 12,
    borderRadius: 8,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: '#2a2a2a',
  },
  segmentInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 4,
    gap: 8,
  },
  segmentNumber: {
    fontSize: 14,
    fontWeight: '600',
    color: '#ffffff',
  },
  segmentDuration: {
    fontSize: 14,
    fontWeight: '600',
    color: '#6366f1',
  },
  segmentSource: {
    fontSize: 12,
    color: '#9ca3af',
  },
  segmentPath: {
    fontSize: 10,
    color: '#6b7280',
    fontFamily: Platform.OS === 'ios' ? 'Courier' : 'monospace',
  },
  actionsContainer: {
    gap: 12,
    marginBottom: 24,
  },
  actionButton: {
    padding: 16,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  primaryButton: {
    backgroundColor: '#6366f1',
  },
  secondaryButton: {
    backgroundColor: '#6b7280',
  },
  testButton: {
    backgroundColor: '#8b5cf6',
  },
  buttonDisabled: {
    backgroundColor: '#2a2a2a',
    opacity: 0.6,
  },
  actionButtonText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#ffffff',
  },
  debugContainer: {
    backgroundColor: '#1a1a1a',
    padding: 12,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#2a2a2a',
  },
  debugTitle: {
    fontSize: 12,
    fontWeight: '600',
    color: '#9ca3af',
    marginBottom: 8,
  },
  debugText: {
    fontSize: 11,
    color: '#6b7280',
    fontFamily: Platform.OS === 'ios' ? 'Courier' : 'monospace',
    marginBottom: 2,
  },
});
