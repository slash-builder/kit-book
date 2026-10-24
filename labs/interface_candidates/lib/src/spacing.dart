// Spacing and size constants. These are the ONLY literal numbers the
// components use for layout; every colour and every text style comes from
// Theme.of(context). When the design system's tokens replace the Material lookups,
// replace these with its spacing scale.

/// Smallest gap (icon to text).
const double kGapXs = 4;

/// Small gap.
const double kGapS = 8;

/// Medium gap.
const double kGapM = 12;

/// Large gap (page padding, between blocks).
const double kGapL = 16;

/// Extra large gap.
const double kGapXl = 24;

/// Minimum size of anything a person can tap or click (WCAG 2.5.8 and the
/// Material/Android guideline: 48 dp).
const double kMinTapTarget = 48;

/// Diameter of the status dot in [StatusDotRow].
const double kDotSize = 12;

/// Width at and above which [PageScaffold.masterDetail] shows both panes.
const double kWideBreakpoint = 720;

/// Default width of the master pane.
const double kMasterPaneWidth = 300;

/// Widest a centred message block (empty or error state) grows.
const double kStateMaxWidth = 420;
