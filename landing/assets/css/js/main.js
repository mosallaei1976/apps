"use strict";

// Fill this only after the real web app is deployed and tested.
const config = {
  webAppUrl: "",
};

const messages = {
  fa: {
    title: "Persian Transcriber | رونویسی محلی گفتار فارسی",
    description:
      "Persian Transcriber؛ پروژهٔ متن‌باز رونویسی گفتار فارسی با هدف پردازش محلی و حفظ حریم خصوصی.",
    navLabel: "ناوبری اصلی",
    skipLink: "رفتن به محتوای اصلی",
    languageButton: "English",
    languageButtonLabel: "Switch to English",
    navFeatures: "ویژگی‌ها",
    navArchitecture: "معماری",
    navPrivacy: "حریم خصوصی",
    navAbout: "درباره",
    eyebrow: "متن‌باز · پردازش محلی · در حال توسعه",
    heroTitle: "گفتار فارسی را به متن تبدیل کنید؛ روی دستگاه خودتان.",
    heroDescription:
      "Persian Transcriber در حال توسعه است تا رونویسی گفتار فارسی بدون آپلود صوت برای پردازش انجام شود. پس از آماده‌سازی اولیه، پردازش در نسخه‌های پشتیبانی‌شده به‌صورت محلی انجام خواهد شد.",
    comingSoon: "به‌زودی",
    webButton: "اجرای نسخهٔ وب / PWA",
    webPending: "نسخهٔ وب هنوز منتشر نشده است.",
    webReady: "نسخهٔ وب در دسترس است. نصب آن به امکانات مرورگر شما بستگی دارد.",
    previewTag: "نمای شماتیک",
    previewText: "صدای شما، روی دستگاه شما.",
    previewCaption: "این تصویر، پیش‌نمایش عملکرد واقعی اپ نیست.",
    featuresEyebrow: "هدف محصول",
    featuresTitle: "برای رونویسی قابل‌کنترل ساخته می‌شود",
    featureOneTitle: "پردازش محلی",
    featureOneBody:
      "هدف، رونویسی بدون ارسال فایل صوتی به سرویس پردازش ابری است.",
    featureTwoTitle: "متن‌باز",
    featureTwoBody: "کد پروژه برای بررسی و مشارکت عمومی منتشر خواهد شد.",
    featureThreeTitle: "فارسی و انگلیسی",
    featureThreeBody: "رابط کاربری برای هر دو زبان و جهت نوشتار طراحی می‌شود.",
    architectureEyebrow: "معماری",
    architectureTitle: "دو مسیر اجرا، یک اصل مشترک",
    architectureBody:
      "نسخه‌های نیتیو و وب از مسیرهای اجرایی متفاوت استفاده می‌کنند. پردازش وب در محدودیت‌های حافظه و امکانات مرورگر انجام می‌شود؛ بنابراین کارایی آن لزوماً با اپ نیتیو یکسان نیست.",
    privacyEyebrow: "حریم خصوصی",
    privacyTitle: "بدون ردیاب در این لندینگ",
    privacyBody:
      "این صفحه اسکریپت تحلیل بازدید، پیکسل ردیابی یا فونت بارگذاری‌شده از سرویس شخص ثالث ندارد. بازدید از سایت و دریافت اولیهٔ اپ همچنان شامل ارتباط معمول با میزبان وب است.",
    aboutEyebrow: "دربارهٔ پروژه",
    aboutTitle: "ساخته‌شده با نگاه متن‌باز",
    aboutBody:
      "معمار پروژه: سید محمد مصلائی. مسیر حمایت مالی و همکاری سازمانی پس از آماده‌شدن مقصدهای رسمی به این صفحه اضافه می‌شود.",
    contactLink: "تماس در تلگرام: @msli1976",
    footerNote: "وضعیت: پیش از انتشار عمومی",
    releaseTitle: (platform) => `${platform} — به‌زودی`,
    releaseBody:
      "این نسخه هنوز منتشر نشده است. در این مرحله ایمیل یا اطلاعات تماس برای اعلان انتشار جمع‌آوری نمی‌شود.",
    closeButton: "بستن",
  },

  en: {
    title: "Persian Transcriber | On-Device Persian Speech-to-Text",
    description:
      "Persian Transcriber is an open-source project for privacy-first, on-device Persian speech-to-text.",
    navLabel: "Main navigation",
    skipLink: "Skip to main content",
    languageButton: "فارسی",
    languageButtonLabel: "تغییر زبان به فارسی",
    navFeatures: "Features",
    navArchitecture: "Architecture",
    navPrivacy: "Privacy",
    navAbout: "About",
    eyebrow: "Open source · On-device · In development",
    heroTitle: "Transcribe Persian speech on your own device.",
    heroDescription:
      "Persian Transcriber is being developed to transcribe Persian speech without uploading audio for processing. After initial setup, supported releases will process audio locally.",
    comingSoon: "Coming soon",
    webButton: "Run web app / PWA",
    webPending: "The web app has not been released yet.",
    webReady:
      "The web app is available. Installation depends on your browser's capabilities.",
    previewTag: "Concept preview",
    previewText: "Your audio, on your device.",
    previewCaption: "This illustration is not a preview of the working app.",
    featuresEyebrow: "Product direction",
    featuresTitle: "Built for transcription you control",
    featureOneTitle: "Local processing",
    featureOneBody:
      "The goal is transcription without sending audio to a cloud processing service.",
    featureTwoTitle: "Open source",
    featureTwoBody:
      "The project source will be published for public review and contributions.",
    featureThreeTitle: "Persian and English",
    featureThreeBody:
      "The interface is designed for both languages and writing directions.",
    architectureEyebrow: "Architecture",
    architectureTitle: "Two execution paths, one guiding principle",
    architectureBody:
      "Native and web releases use different execution paths. Browser processing has memory and platform constraints, so its performance may differ from native apps.",
    privacyEyebrow: "Privacy",
    privacyTitle: "No trackers on this landing page",
    privacyBody:
      "This page has no analytics scripts, tracking pixels, or fonts loaded from third-party services. Visiting the site and downloading the app still involve ordinary connections to the web host.",
    aboutEyebrow: "About the project",
    aboutTitle: "Built with an open-source mindset",
    aboutBody:
      "Project architect: Seyed Mohammad Mosallaei. Sponsorship and enterprise contact options will be added when their official destinations are ready.",
    contactLink: "Contact on Telegram: @msli1976",
    footerNote: "Status: Pre-release",
    releaseTitle: (platform) => `${platform} — Coming soon`,
    releaseBody:
      "This release is not available yet. This page does not currently collect email addresses or contact details for release alerts.",
    closeButton: "Close",
  },
};

const root = document.documentElement;
const languageButton = document.querySelector("#language-button");
const webAppButton = document.querySelector("#web-app-button");
const webStatus = document.querySelector("#web-status");
const releaseDialog = document.querySelector("#release-dialog");

function storedLanguage() {
  try {
    return localStorage.getItem("pt-language") === "en" ? "en" : "fa";
  } catch {
    return "fa";
  }
}

function setLanguage(lang) {
  const copy = messages[lang];

  root.lang = lang;
  root.dir = lang === "fa" ? "rtl" : "ltr";
  document.title = copy.title;

  document
    .querySelector('meta[name="description"]')
    .setAttribute("content", copy.description);

  document.querySelector(".skip-link").textContent = copy.skipLink;
  document.querySelector("#main-nav").setAttribute("aria-label", copy.navLabel);
  document.querySelector(".cta-group").setAttribute(
    "aria-label",
    lang === "fa" ? "گزینه‌های دریافت" : "Download options"
  );
  document.querySelector(".preview").setAttribute(
    "aria-label",
    lang === "fa" ? "نمای شماتیک محصول" : "Concept illustration"
  );

  document.querySelectorAll("[data-i18n]").forEach((element) => {
    element.textContent = copy[element.dataset.i18n];
  });

  languageButton.textContent = copy.languageButton;
  languageButton.setAttribute("aria-label", copy.languageButtonLabel);
  webStatus.textContent = config.webAppUrl ? copy.webReady : copy.webPending;

  try {
    localStorage.setItem("pt-language", lang);
  } catch {
    // The language switch still works when storage is unavailable.
  }
}

webAppButton.disabled = !config.webAppUrl;

webAppButton.addEventListener("click", () => {
  if (config.webAppUrl) {
    window.location.assign(config.webAppUrl);
  }
});

languageButton.addEventListener("click", () => {
  setLanguage(root.lang === "fa" ? "en" : "fa");
});

document.querySelectorAll("[data-store]").forEach((button) => {
  button.addEventListener("click", () => {
    const copy = messages[root.lang];

    document.querySelector("#release-dialog-title").textContent =
      copy.releaseTitle(button.dataset.store);
    document.querySelector("#release-dialog-message").textContent =
      copy.releaseBody;

    releaseDialog.showModal();
  });
});

document.querySelector("#year").textContent = new Date().getFullYear();
setLanguage(storedLanguage());
