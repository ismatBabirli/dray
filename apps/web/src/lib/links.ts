export const REPO = "https://github.com/ismatbabirli/wain";

/// The newest stable dmg, off the R2 mirror rather than GitHub, whose release
/// CDN has had 42MB take 45 minutes. release.yml overwrites this one key on
/// every stable release, so the button needs no build-time lookup; betas leave
/// it alone, the beta channel being the updater's and not this page's.
export const DOWNLOAD = "https://downloads.wainhq.com/Wain_universal.dmg";

/// The server install. `public/install.sh` resolves the newest `cli-v*` tag
/// itself, so this line never needs a version in it.
export const INSTALL_LINE = "curl -fsSL https://www.wainhq.com/install.sh | sh";

/// The iPhone app on the App Store. Empty until Wain's own is published: the
/// id that was here was upstream's app, and every iPhone link hides while this is "".
export const APP_STORE = "";

/// Where feedback goes: the repo's issues, until Wain has a social account of its own.
export const FEEDBACK = `${REPO}/issues`;

export const COMPANY = "Wain";

/// Where people write for help, and where account deletion requests go.
export const SUPPORT_EMAIL = "support@wainhq.com";

// No sponsor checkout: upstream's Dodo products paid upstream, so the support
// page, its links and the Support component were removed (FORK-PLAN.md §5).

/// What the nav shows when GitHub cannot be asked. Bump it now and then so a
/// rate-limited render does not undercount by much.
export const STARS_FALLBACK = 0;
