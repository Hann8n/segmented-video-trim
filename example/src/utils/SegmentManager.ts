/**
 * Segment Manager - Single source of truth for video segments
 *
 * Core principles:
 * - All durations in seconds (consistent units throughout)
 * - Simple, predictable API
 * - No side effects or complex state management
 */

export interface Segment {
  duration: number; // Duration in seconds
  video: { uri: string };
  sourceType?: 'camera' | 'gallery';
}

export class SegmentManager {
  private segments: Segment[] = [];
  private maxDuration: number;

  constructor(maxDuration: number) {
    this.maxDuration = maxDuration;
  }

  setMaxDuration(maxDuration: number): void {
    this.maxDuration = maxDuration;
  }

  getMaxDuration(): number {
    return this.maxDuration;
  }

  getSegments(): Segment[] {
    return [...this.segments];
  }

  getSegmentCount(): number {
    return this.segments.length;
  }

  getTotalDuration(): number {
    return this.segments.reduce((sum, segment) => sum + segment.duration, 0);
  }

  getAvailableTime(): number {
    // Use precise values (no rounding) so users can reach the maximum
    return Math.max(0, this.maxDuration - this.getTotalDuration());
  }

  canAddSegment(duration: number): boolean {
    // Use precise values (no rounding) for calculations
    // Display values are rounded for UI simplicity, but calculations use exact values
    return (
      duration > 0 && this.getTotalDuration() + duration <= this.maxDuration
    );
  }

  addSegment(segment: Segment): boolean {
    if (!this.canAddSegment(segment.duration)) {
      return false;
    }
    this.segments.push(segment);
    return true;
  }

  removeLastSegment(): Segment | null {
    return this.segments.pop() || null;
  }

  clear(): void {
    this.segments = [];
  }

  hasSegments(): boolean {
    return this.segments.length > 0;
  }
}
