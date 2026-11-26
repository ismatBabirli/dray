import { preload } from "react-dom";
import { DownloadButton, PhonesLine, WindowsButton } from "@/components/DownloadButton";
import { LinuxMenu } from "@/components/LinuxMenu";
import { Hero as AppWindow } from "@/components/illustrations/Hero";
import h from "./hero.module.css";
import { HeroBackdrop } from "./HeroBackdrop";
import { PhoneDownloads } from "./PhoneDownloads";
import { SiteNav } from "./SiteNav";

/// The top of the page: nav, headline and the live app window, over the
/// pixel-blue backdrop.
export function Hero() {
  // The phone still is the page's LCP, and lazy loading started it only after
  // layout. A preload in <head> starts it at once for the system's scheme; a
  // saved pick that disagrees falls back to the lazy <img> below.
  preload("/hero-mobile.webp", { as: "image", fetchPriority: "high", media: "(max-width: 639px) and (prefers-color-scheme: dark)" });
  preload("/hero-mobile-light.webp", { as: "image", fetchPriority: "high", media: "(max-width: 639px) and (prefers-color-scheme: light)" });

  return (
    <>
    <header id="hero" className="relative overflow-clip bg-black px-5 pb-14 sm:px-8 sm:pb-10 light:bg-white">
      {/* Down by the "Also on" line's 36px, so the field still starts under
          it. A phone's buttons come one or two to a column, so its field
          hangs off the window instead, below. */}
      <HeroBackdrop top="top-9 max-sm:hidden" />

      <div className="relative mx-auto w-full max-w-[960px]">
        <SiteNav />

        {/* The line's 20px and its 16px gap come off the top padding, so the
            headline stays where it was. */}
        <div className="pt-7 sm:pt-[81px] lg:ml-[102px] lg:max-w-[756px]">
          <p className="mb-4 text-[14px] leading-5 tracking-[-0.01em] text-white/30 light:text-black/40">Free and open source</p>
          <h1 className="font-inter text-[30px] leading-[34px] font-[350] tracking-[-0.03em] text-balance text-white sm:text-[46px] light:text-[#0A0A0A] sm:leading-[54px]">
            Work on dozens of coding tasks without getting overwhelmed.
          </h1>
          {/* A phone gets its own apps; the desktop ones are a line under them. */}
          <PhoneDownloads className="sm:hidden" />
          <div className="mt-8 flex flex-wrap items-start justify-between gap-4 pr-5 max-sm:hidden">
            <div className="flex flex-wrap items-center gap-3">
              <DownloadButton from="hero" className="inline-flex h-10 items-center gap-2 rounded-[6px] bg-white px-4 text-[14px] leading-5 font-medium text-[#0B0B0F] shadow-[inset_0_-1px_0_#4D4C4C,0_1px_2px_#00000040,0_10px_28px_-10px_#00000099] transition-opacity hover:opacity-90 [&>svg]:-mt-0.5 light:bg-[#0A0A0A] light:text-white light:shadow-[inset_0_-1px_0_#000,0_1px_2px_#00000040]" />
              <LinuxMenu className="inline-flex h-10 cursor-pointer items-center gap-2 rounded-[6px] border border-white/20 px-4 text-[14px] leading-5 font-medium text-white transition-colors hover:bg-white/10 light:border-black/15 light:text-[#0A0A0A] light:hover:bg-black/5" />
              <WindowsButton from="hero" beta="text-[#A1A1A1] light:text-[#6B6B6B]" className="inline-flex h-10 items-center gap-2 rounded-[6px] border border-white/20 px-4 text-[14px] leading-5 font-medium text-white transition-colors hover:bg-white/10 light:border-black/15 light:text-[#0A0A0A] light:hover:bg-black/5" />
            </div>
          </div>
          <PhonesLine className="mt-4 max-sm:hidden text-[14px] leading-5 tracking-[-0.01em] text-white/50 light:text-black/50" />
        </div>

        <div className="relative mt-12 sm:left-1/2 sm:w-[min(1200px,calc(100vw-64px))] sm:-translate-x-1/2 lg:rounded-[12px] lg:shadow-[0_2px_50px_12px_#0000004D] light:lg:shadow-none">
          {/* The field's top edge 22px above the window, where the desktop
              one lands. */}
          <HeroBackdrop id="hero-phone" top="-top-[382px] sm:hidden" />
          {/* The live window wants a desktop's width; a phone gets a still of
              it instead of a sideways-scrolling miniature. */}
          <div className={`relative max-sm:hidden ${h.liveCursor}`}>
            <AppWindow />
          </div>
          {/* One per scheme, since the toggle can disagree with the system a
              <picture> media query would follow. Lazy, so the hidden one costs
              nothing. */}
          <img
            src="/hero-mobile.webp"
            alt="The Wain window: sessions in the sidebar, an agent's report in the chat, and its pull request's checks in the side panel."
            width={1200}
            height={720}
            loading="lazy"
            className="relative h-auto w-full rounded-[6px] sm:hidden light:hidden"
          />
          <img
            src="/hero-mobile-light.webp"
            alt="The Wain window: sessions in the sidebar, an agent's report in the chat, and its pull request's checks in the side panel."
            width={1440}
            height={864}
            loading="lazy"
            className="relative hidden h-auto w-full rounded-[6px] shadow-[0_0_0_1px_#00000014] light:block light:sm:hidden"
          />
        </div>
      </div>
    </header>
    </>
  );
}
