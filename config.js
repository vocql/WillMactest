// ==========================================================================
//  TURN APPLICATIONS ON / OFF  (just change true / false, then commit)
//    true  = open        false = closed (card is greyed out, can't be clicked)
// ==========================================================================
window.WM_OPEN = {
  mod:     true,   // Moderator
  creator: true,   // Creator
  events:  true,   // Event Host
  partner: true,   // Partnership
  appeal:  true    // Appeals
};

// ============ EDIT THIS FILE ============
// Everything on the site comes from here. After editing, commit the change on GitHub.
window.WM_CONFIG = {
  // ---- 1) Saving applications (powers the /applications dashboard) ----
  // Free Supabase project. See README.md, "Step 2". Paste both values from
  // Supabase > Project Settings > API (Project URL and the anon / publishable key).
  supabaseUrl: "https://czhiiemivswifybhfuxr.supabase.co",
  supabaseKey: "sb_publishable_Lef9q2NJeJbyjdBzOY46Nw_QrZGgTd7",

  // ---- 2) Discord alert (optional but recommended) ----
  // Channel settings > Integrations > Webhooks > New Webhook > Copy URL
  discordWebhook: "",

  // ---- 3) Google Form copy (optional) ----
  // entry.XXXX ids in question order (see README). Leave entries empty to skip.
  googleForm: {
    formId: "1FAIpQLSfo13rG_eUvgKL9OgxLlCqfXij4BxSFZz3Qny7CJv8qRTwfww",
    entries: []
  },

  applicationsOpen: true,
  cooldownMinutes: 30,   // how long before the same browser can apply again
  minAnswerLength: 20,   // minimum characters for the long answers

  requirements: [
    "Must be a member of the server for 2-3+ months.",
    "Must have 2FA enabled on your Discord account.",
    "Must be familiar with how the server runs and is operated."
  ],

  // Same picture links as before
  logo: "https://images.guns.lol/637041cec591a6ab27615f0e2db44d08f3ce0c55/p6IK2p.webp",
  background: "https://images.guns.lol/637041cec591a6ab27615f0e2db44d08f3ce0c55/96kvVB.jpg",
  staff: [
    { name: "Will Mac", role: "Owner", img: "https://images.guns.lol/637041cec591a6ab27615f0e2db44d08f3ce0c55/p6IK2p.webp" },
    { name: "Debug.exe", role: "Co-Owner", img: "https://images.guns.lol/637041cec591a6ab27615f0e2db44d08f3ce0c55/fu02p0.webp" },
    { name: "Voqcl", role: "Admin", img: "https://images.guns.lol/637041cec591a6ab27615f0e2db44d08f3ce0c55/jQl2KH.png" },
    { name: "Kelpie", role: "Lead Moderator", img: "https://images.guns.lol/637041cec591a6ab27615f0e2db44d08f3ce0c55/K1uxkp.webp" },
    { name: "Spizike", role: "Lead Moderator", img: "https://images.guns.lol/637041cec591a6ab27615f0e2db44d08f3ce0c55/1BPOl7.webp" },
    { name: "Myguyvr", role: "Moderator", img: "https://images.guns.lol/637041cec591a6ab27615f0e2db44d08f3ce0c55/3mcWjr.webp" },
    { name: "Dean", role: "Moderator", img: "https://images.guns.lol/637041cec591a6ab27615f0e2db44d08f3ce0c55/uZC5kf.webp" },
    { name: "Khxal", role: "Moderator", img: "https://images.guns.lol/637041cec591a6ab27615f0e2db44d08f3ce0c55/sg4sJp.webp" },
    { name: "Chrxmio", role: "Moderator", img: "https://images.guns.lol/637041cec591a6ab27615f0e2db44d08f3ce0c55/4tUobL.webp" },
    { name: "TyriusTheVA", role: "Moderator", img: "https://images.guns.lol/637041cec591a6ab27615f0e2db44d08f3ce0c55/JPda0S.webp" },
    { name: "LilSkeptrim", role: "Moderator", img: "https://images.guns.lol/637041cec591a6ab27615f0e2db44d08f3ce0c55/iN1Hni.webp" },
    { name: "Tordai", role: "Moderator", img: "https://images.guns.lol/637041cec591a6ab27615f0e2db44d08f3ce0c55/dwpdQt.png" },
    { name: "Tyler Jones", role: "Moderator", img: "https://images.guns.lol/637041cec591a6ab27615f0e2db44d08f3ce0c55/3fAq9X.webp" },
  ],

  faq: [
    ["Why authorize your Discord account?", "Authorization allows you to track your application status and receive updates on its progress."],
    ["Who can apply?", "Any member who has been in the server for 3+ months, has 2FA enabled, and is familiar with how the server runs and is operated."],
    ["Why do I need 2FA?", "Moderators have powerful permissions. Two-factor authentication keeps staff accounts safe from being hijacked."],
    ["What happens after I apply?", "The staff team reviews every application. If you're shortlisted, we'll contact you on Discord, so keep your DMs open."],
    ["Does applying guarantee I'll be accepted?", "No. We read every application, but spots are limited and we only accept the best fits."]
  ],

  // `short` is the label staff see. `tip` is a small hint shown to applicants.
  questions: [
    { label: "What is your Discord name?", hint: "(e.g. WillMacGTA)", short: "Discord name", type: "text", max: 60,
      tip: "So we know who to contact if you're shortlisted." },
    { label: "Why do you want to be staff?", short: "Why staff?", type: "area", max: 1000,
      tip: "Tell us what drives you. Specific reasons beat generic ones." },
    { label: "Have you had any other experiences on Discord like this? If so, what?", short: "Other experience", type: "area", max: 1000,
      tip: "Servers you've moderated, roles you've held, how long for." },
    { label: "How active are you on Discord every day?", short: "Daily activity", type: "area", max: 1000,
      tip: "Roughly which hours and how many per day." },
    { label: "How would you deal with someone who's spamming?", short: "Dealing with spam", type: "area", max: 1000,
      tip: "Walk us through your steps, from first reaction to final action." },
    { label: "How would you deal with a raider?", short: "Dealing with a raider", type: "area", max: 1000,
      tip: "Think speed: what do you do in the first minute?" },
    { label: "How do you warn, kick and ban people?", short: "Warn, kick and ban", type: "area", max: 1000,
      tip: "When is each one appropriate, and how do you stay fair?" },
    { label: "How would you benefit the server? What would you change, and why?", short: "Benefit to the server", type: "area", max: 1000,
      tip: "One or two concrete ideas are better than a long list." }
  ]
};

// ============ APPLICATION TYPES ============
// Each type has its own questions, requirements and confirm text. The Moderator type reuses the
// original `questions` / `requirements` above, so nothing was removed. To add another type, copy a block.
// RULES: the FIRST question of every type must be the Discord name. `id` must be short, lowercase letters only.
// `open: false` closes just that type. `discordWebhook` (optional) sends that type to its own channel.
window.WM_CONFIG.types = [
  {
    id: "mod", title: "Moderator", open: true, verb: "Apply for staff",
    blurb: "Help keep the server welcoming, active and well-managed.",
    lead: "We're looking for a few new moderators to help keep the server welcoming, active, and well-managed.",
    note: "Accounts that are new or have recently joined the server will not be accepted.",
    confirm: "I confirm I have been in the server for 3+ months, have 2FA enabled on my Discord account, and am familiar with how the server runs and is operated.",
    requirements: window.WM_CONFIG.requirements,
    questions: window.WM_CONFIG.questions,
    googleForm: window.WM_CONFIG.googleForm
  },
  {
    id: "creator", title: "Creator", open: true, verb: "Apply as a creator",
    blurb: "Create GTA VI content? Apply for the Creator role to get recognized, featured, and have your content spotlighted in the community!",
    lead: "Do you make videos, streams or clips? Apply for the Creator role and get your content shown to the community.",
    note: "You must own the channel you submit. Re-uploads and clip-farm accounts will not be accepted.",
    confirm: "I confirm I own the channel(s) I submitted and that everything I wrote is true.",
    requirements: [
      "Must be a member of the server.",
      "Must post original content regularly.",
      "Must follow the server rules and each platform's rules."
    ],
    questions: [
      { label: "What is your Discord name?", hint: "(e.g. WillMacGTA)", short: "Discord name", type: "text", max: 60, tip: "So we know who to contact." },
      { label: "Link to your main channel", hint: "(YouTube, Twitch, TikTok...)", short: "Channel link", type: "text", max: 200, tip: "Paste the full link. One main channel is enough." },
      { label: "What kind of content do you make?", short: "Content type", type: "area", max: 1000, tip: "Games, formats, style. What makes your content yours?" },
      { label: "How big is your audience?", short: "Audience size", type: "area", max: 1000, tip: "Followers/subscribers and roughly how many views you get per video or stream." },
      { label: "How often do you upload or stream?", short: "Schedule", type: "area", max: 1000, tip: "Days, times and how consistent you've been." },
      { label: "Why do you want the Creator role?", short: "Why creator?", type: "area", max: 1000, tip: "What do you want from the community, and what will you give back?" },
      { label: "Any ideas for GTA VI or community content?", short: "Content ideas", type: "area", max: 1000, tip: "One or two concrete ideas, collabs or series." }
    ]
  },
  {
    id: "events", title: "Event Host", open: true, verb: "Apply as an event host",
    blurb: "Run game nights, giveaways and community events.",
    lead: "Want to run events for the community? Tell us what you'd host and when you're free.",
    note: "Hosts must be reliable. Please only apply if you can commit to a regular slot.",
    confirm: "I confirm I can commit to hosting events and will follow the server rules while hosting.",
    requirements: [
      "Must be a member of the server for 1+ month.",
      "Must be able to host at set times.",
      "Must stay calm and fair while running events."
    ],
    questions: [
      { label: "What is your Discord name?", hint: "(e.g. WillMacGTA)", short: "Discord name", type: "text", max: 60, tip: "So we know who to contact." },
      { label: "What kind of events would you host?", short: "Event types", type: "area", max: 1000, tip: "Game nights, quizzes, giveaways, watch parties..." },
      { label: "Have you hosted events before? If so, where?", short: "Experience", type: "area", max: 1000, tip: "Servers, streams, how many people showed up." },
      { label: "When are you available, and what is your timezone?", short: "Availability", type: "area", max: 1000, tip: "Days and hours you could host each week." },
      { label: "Describe one event you'd run, step by step.", short: "Event idea", type: "area", max: 1000, tip: "Rules, prizes, how long, how people join." },
      { label: "How would you handle someone disrupting your event?", short: "Disruptions", type: "area", max: 1000, tip: "Cheaters, trolls, arguments. What do you do first?" }
    ]
  },
  {
    id: "partner", title: "Partnership", open: true, verb: "Apply for a partnership",
    blurb: "Own a server or brand? Propose a partnership or collab.",
    lead: "Own a server, channel or brand? Tell us about it and what you'd like to do together.",
    note: "We only partner with active, safe communities that follow Discord's rules.",
    confirm: "I confirm I represent the server/brand I described and have permission to propose a partnership.",
    requirements: [
      "Must own or manage the server or brand.",
      "Must follow Discord's Terms and Community Guidelines.",
      "Must have an active community."
    ],
    questions: [
      { label: "What is your Discord name?", hint: "(e.g. WillMacGTA)", short: "Discord name", type: "text", max: 60, tip: "The person we should contact." },
      { label: "Name of your server or brand, and a link", short: "Server / brand", type: "text", max: 200, tip: "Permanent invite link or website." },
      { label: "How many members or followers do you have?", short: "Size", type: "area", max: 1000, tip: "Total members and how many are active." },
      { label: "What partnership are you proposing?", short: "Proposal", type: "area", max: 1000, tip: "Collab, shout-outs, joint events, etc." },
      { label: "What would each side get out of it?", short: "Benefits", type: "area", max: 1000, tip: "Be specific about what you offer us and what you'd like." },
      { label: "Any other way to contact you?", short: "Other contact", type: "area", max: 1000, tip: "Email, X, anything we can use besides Discord." }
    ]
  }
];

// ============ APPEALS ============
// Appeals are an application type. ONE staff member (Moderator, Lead or Admin) reviews each appeal. No voting.
window.WM_CONFIG.types.push({
  id: "appeal", title: "Appeal", open: true, verb: "Send an appeal",
  blurb: "Think a ban, mute, kick or warning was wrong? Send one calm, honest appeal. One staff member who wasn't involved reviews it and gives you a clear answer.",
  lead: "Tell us what happened and why the punishment should be lifted. Be honest and specific. One staff member who did not issue your punishment will review it.",
  note: "You can only have one open appeal. If it is denied you can appeal again after 7 days.",
  confirm: "I confirm everything I wrote is true and I understand that lying or sending repeat appeals can get my appeal denied.",
  requirements: [
    "Log in with the Discord account that was punished.",
    "Only one open appeal at a time.",
    "If denied, wait 7 days before appealing again.",
    "Do not argue the punishment in chat or DMs. Use this page."
  ],
  questions: [
    { label: "What is your Discord username and ID?", hint: "(e.g. voqcl, 1271246652421701633)", short: "Username + ID", type: "text", max: 100, tip: "Needed so staff can look up your history." },
    { label: "What punishment are you appealing?", hint: "(ban, mute, kick, warning)", short: "Punishment", type: "area", max: 1000, tip: "What was it, when did it happen and what reason were you given?" },
    { label: "Which staff member punished you?", hint: "(or write: not sure)", short: "Punished by", type: "text", max: 60, tip: "This keeps that person away from reviewing your appeal." },
    { label: "Do you understand why you were punished?", short: "Understands the issue", type: "area", max: 1000, tip: "Explain what you did in your own words. No blaming others." },
    { label: "Why should we lift it?", short: "Why lift it", type: "area", max: 1000, tip: "New context, a mistake on our side, or real accountability." },
    { label: "What will you change going forward?", short: "What changes", type: "area", max: 1000, tip: "Be specific about how you will follow the rules." },
    { label: "Anything else we should know?", short: "Anything else", type: "area", max: 1000, tip: "Links, screenshots or context. Write none if there is nothing." }
  ]
});

// ============ STAFF MESSAGE PRESETS (used by the dashboard) ============
// {name} becomes the member's name. Edit freely.
window.WM_CONFIG.presets = {
  appeal: [
    ["Accepted", "Hi {name}, thanks for your patience. After reviewing your appeal and your history we've decided to lift your punishment. You're on probation for 1-2 weeks, so please re-read the rules. Any rule break during probation means an instant ban."],
    ["Accepted (reduced)", "Hi {name}, we reviewed your appeal and agree the punishment was harsher than needed, so we've reduced it. Thanks for staying calm and honest. Please keep the rules in mind."],
    ["Denied", "Hi {name}, thanks for appealing. We checked the logs, evidence and your history and we're keeping the punishment. You can appeal again after 7 days if you have new information."],
    ["Denied (no accountability)", "Hi {name}, we're keeping the punishment. Your appeal didn't show that you understand what went wrong or what will change. You can appeal again after 7 days. Please be specific next time."],
    ["Denied (final)", "Hi {name}, this punishment was for a serious rule break and the decision is final. We won't accept further appeals for it."],
    ["Need more details", "Hi {name}, we need a bit more detail before we can decide. Please explain what happened in your own words and what you'll do differently. Reply on your appeal page."],
    ["Need evidence", "Hi {name}, can you share any screenshots, links or context that support your side? Reply on your appeal page and we'll continue the review."],
    ["Escalated", "Hi {name}, your appeal has been passed to an admin for a closer look. You don't need to do anything. We'll update you here."]
  ],
  app: [
    ["Under review", "A staff member is reading your application now."],
    ["Interview", "You've been shortlisted! We'd like a short interview. Please keep your DMs open and reply with your availability and timezone."],
    ["Check your DMs", "We sent you a Discord DM. Please reply when you can."],
    ["Need more info", "We need a bit more info about your experience. Please reply to our DM."],
    ["Approved", "Congratulations! Your application has been approved. Check your DMs for next steps and please read the Staff Handbook first."],
    ["Denied (general)", "Thanks for applying. After careful review we've decided not to move forward this time. You're welcome to apply again later."],
    ["Denied (answers too short)", "Thanks for applying. Your answers were too short for us to judge properly. You're welcome to apply again with more detailed, specific answers."],
    ["Denied (too new)", "Thanks for applying. We need members who've been around longer and know how the server runs. Please apply again once you've been here a bit longer."],
    ["On hold", "Your application is on hold while we finish reviewing others. You don't need to do anything. We'll update you soon."]
  ]
};

// ---- White icons for each application type (inline SVG, drawn in white) ----
// To use your own, set `icon: "https://link-to-a-white-png-or-svg"` on a type above.
(function () {
  const svg = p => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + p + '</svg>';
  window.WM_CONFIG.icons = {
    mod:     svg('<path d="M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z"/><path d="M8.7 12.2l2.3 2.3 4.3-4.6"/>'),
    creator: svg('<rect x="3" y="6" width="13" height="12" rx="2.5"/><path d="M16 10.5l5-3v9l-5-3"/>'),
    events:  svg('<rect x="3.5" y="5" width="17" height="15.5" rx="2.5"/><path d="M8 3v4M16 3v4M3.5 10h17"/><path d="M12 12.6l1 2 2.2.3-1.6 1.5.4 2.2-2-1.1-2 1.1.4-2.2-1.6-1.5 2.2-.3z"/>'),
    appeal:  svg('<path d="M12 4v16M7 20h10"/><path d="M5 7h14"/><path d="M5 7l-3 7a3.5 3.5 0 0 0 6 0z"/><path d="M19 7l-3 7a3.5 3.5 0 0 0 6 0z"/>'),
    partner: svg('<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>')
  };
})();

// ---- Apply the on/off list at the top of this file (leave this alone) ----
window.WM_CONFIG.types.forEach(function (t) {
  if (t.id in window.WM_OPEN) t.open = !!window.WM_OPEN[t.id];
});
