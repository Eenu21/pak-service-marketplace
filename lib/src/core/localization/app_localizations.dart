import 'package:flutter/material.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const supportedLocales = <Locale>[Locale('en'), Locale('ur')];

  static AppLocalizations of(BuildContext context) {
    final localizations = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );
    assert(localizations != null, 'No AppLocalizations found in context');
    return localizations!;
  }

  static const Map<String, Map<String, String>>
  _translations = <String, Map<String, String>>{
    'en': <String, String>{
      'accept': 'Accept',
      'accept_terms': 'I accept Terms & Conditions',
      'account_details': 'Account Details',
      'account_trust_status': 'Account Trust Status',
      'account_type': 'Account Type',
      'actions': 'Actions',
      'actor': 'Actor',
      'address': 'Address',
      'admin': 'Admin',
      'already_have_account_login': 'Already have an account? Login',
      'app_name': 'Pak Service Marketplace',
      'auth_intro_subtitle':
          'Trusted local services for Pakistan. Fast booking, verified professionals, and transparent payments.',
      'auth_point_audit': 'Complete timeline and audit logging',
      'auth_point_identity_trust': 'Identity and trust-focused onboarding',
      'auth_point_legal_acceptance': 'Mandatory legal acceptance and records',
      'auth_point_nearby_map': 'Nearby jobs with live map discovery',
      'auth_point_payments': 'Online and cash payment records with fee split',
      'auth_point_privacy_address': 'Privacy-aware address handling',
      'auth_point_verified_pros': 'Verified pros with ratings and reviews',
      'bid_accepted': 'Accepted',
      'bid_category_restricted':
          'Only professionals registered for this category can bid.',
      'bid_not_eligible': 'You are not eligible to bid on this job.',
      'bid_pending': 'Pending',
      'bid_rejected': 'Rejected',
      'bid_submitted': 'Bid submitted',
      'bid_withdrawn': 'Withdrawn',
      'camera_permission_required':
          'Camera permission is required to take a profile photo.',
      'cancel': 'Cancel',
      'cancel_job': 'Cancel Job',
      'cancel_or_dispute': 'Cancel or Raise Dispute',
      'cancellation_disputes': 'Cancellation & Disputes',
      'cancellation_disputes_desc':
          'Cancellation is allowed until service starts. Disputes are logged with timeline evidence and handled by admin.',
      'cancellation_reason': 'Cancellation reason',
      'cash': 'Cash',
      'category_ac_repair': 'AC Repair',
      'category_appliance_repair': 'Appliance Repair',
      'category_carpenter': 'Carpenter',
      'category_cleaning': 'Cleaning',
      'category_electrician': 'Electrician',
      'category_registered_nurse': 'Registered Nurse',
      'category_painter': 'Painter',
      'category_plumbing': 'Plumbing',
      'change_password': 'Change Password',
      'change_password_subtitle': 'Update your account security credentials',
      'change_profile_photo': 'Change Profile Photo',
      'chat': 'Chat',
      'inbox_title': 'Inbox',
      'inbox_subtitle': 'Recent chats first',
      'inbox_search_assigned': 'Search assigned chats by name or job',
      'inbox_recent_chats': 'Recent chats',
      'inbox_empty':
          'No recent conversations yet. Once a job chat starts, it appears here.',
      'choose_photo_source': 'Choose how you want to update your photo.',
      'cnic_pending': 'CNIC Pending',
      'cnic_verified': 'CNIC Verified',
      'completed_jobs': 'Completed Jobs',
      'confirm_password': 'Confirm Password',
      'create_account': 'Create Your Account',
      'current_password': 'Current password',
      'customer': 'Customer',
      'demo_accounts': 'Demo accounts:',
      'demo_admin_creds': 'Admin: admin@pakservice.pk / Admin123!',
      'demo_customer_creds': 'Customer: user@pakservice.pk / User12345!',
      'demo_pro_creds': 'Pro: pro@pakservice.pk / Pro12345!',
      'demo_locked_pro_creds':
          'Locked Pro: prolocked@pakservice.pk / Locked123!',
      'description': 'Description',
      'discover': 'Discover',
      'dispute_reason': 'Dispute reason',
      'earnings': 'Earnings',
      'earnings_dashboard': 'Earnings Dashboard',
      'email': 'Email',
      'email_required': 'Email required',
      'english': 'English',
      'enter_to_accept': 'Enter to accept:',
      'enter_valid_amount': 'Enter a valid amount',
      'exact_address': 'Exact Address',
      'exact_address_helper': 'Visible only after a pro is selected.',
      'exact_address_reveal_after_accept':
          'Exact address will be revealed after job acceptance.',
      'fee': 'Fee',
      'fixed_price': 'Fixed Price (PKR)',
      'full_name': 'Full Name',
      'gallery_permission_required':
          'Gallery permission is required to upload a profile photo.',
      'gross': 'Gross',
      'help_support': 'Help & Support',
      'help_support_desc': 'For urgent issues: support@pakservice.pk',
      'history': 'History',
      'home': 'Home',
      'image_read_error':
          'Unable to read the selected image. Please try again.',
      'job_detail': 'Job Detail',
      'job_history': 'Job History',
      'job_not_found': 'Job not found',
      'job_payment_history': 'Job and Payment History',
      'job_payment_history_subtitle':
          'View your completed work, transactions and status timeline',
      'job_request': 'request',
      'job_requests': 'requests',
      'job_posted_success': 'Job posted and made available to nearby pros.',
      'job_title': 'Job Title',
      'jobs': 'Jobs',
      'jobs_around_you': 'jobs around you',
      'language': 'Language',
      'lifetime': 'Lifetime',
      'linked_payment_account': 'Linked Payment Account',
      'live': 'Live',
      'location_services_disabled':
          'Location services are disabled. Please enable GPS.',
      'location_timeout': 'Unable to get location. Please try again.',
      'location_unavailable': 'Location unavailable. Please try again.',
      'location_permission_nearby':
          'Location permission is required for nearby discovery.',
      'location_permission_post_job':
          'Location permission is required to post a job.',
      'login': 'Login',
      'login_welcome_back': 'Welcome back. Continue with your account.',
      'logout': 'Logout',
      'map_off_saving': 'Map is off to save battery.',
      'mark_completed': 'Mark Completed',
      'method_cash': 'Cash',
      'method_easypaisa': 'Easypaisa',
      'method_jazzcash': 'JazzCash',
      'min_chars_6': 'Min 6 characters',
      'my_jobs': 'My Jobs',
      'nearby': 'Nearby',
      'nearby_header_subtitle':
          'Discover verified requests in your area and bid instantly.',
      'nearby_jobs': 'Nearby Jobs',
      'nearby_pros': 'Nearby Professionals',
      'nearby_pros_subtitle':
          'Find verified professionals around you by category.',
      'nearby_service_jobs': 'Nearby Service Jobs',
      'net': 'Net',
      'new_password': 'New password',
      'no_bids_received': 'No bids received yet.',
      'no_jobs_yet': 'No jobs yet.',
      'no_messages_yet': 'No messages yet.',
      'no_nearby_jobs':
          'No nearby jobs yet. Move around or try another category.',
      'no_nearby_pros': 'No nearby professionals found for this category yet.',
      'no_payment_records': 'No payment records yet.',
      'not_authenticated': 'Not authenticated',
      'not_logged_in': 'Not logged in',
      'notifications': 'Notifications',
      'online': 'Online',
      'open_chat': 'Open Chat',
      'open_chat_subtitle': 'Real-time chat with the other party',
      'optional': 'Optional',
      'password': 'Password',
      'password_mismatch': 'Password and confirm password do not match.',
      'password_updated': 'Password updated',
      'pay_now': 'Pay Now',
      'pay_online_instant_payout': 'Pay Online & Instant Pro Payout',
      'payment_account_helper':
          'JazzCash or Easypaisa account for instant online payouts',
      'payment_completed': 'Completed',
      'payment_failed': 'Failed',
      'payment_initiated': 'Initiated',
      'payment_recorded_closed': 'Payment recorded and job closed',
      'payment_records': 'Payment Records',
      'payment_summary': 'Payment Summary',
      'payments': 'Payments',
      'pending': 'Pending',
      'phone': 'Phone Number',
      'platform_fee': 'Platform fee (7.5%)',
      'platform_fees': 'Platform Fees',
      'police_badge': 'Police Badge',
      'police_badge_optional': 'Police Badge Optional',
      'post': 'Post',
      'post_job': 'Post Job',
      'post_new_job': 'Post a New Job',
      'posted': 'Posted',
      'preferred_categories': 'Preferred Categories',
      'preferred_categories_required':
          'Please select at least one preferred category.',
      'price': 'Price',
      'privacy': 'Privacy',
      'privacy_content':
          'We collect and process user data to operate the platform, improve services, and comply with laws. See the Privacy Policy for details.',
      'privacy_controls': 'Privacy Controls',
      'privacy_controls_desc':
          'Location is used for nearby discovery and navigation. Exact address visibility is role and state controlled.',
      'privacy_mode': 'Privacy Mode',
      'privacy_mode_desc': 'Hide exact job addresses until assignment',
      'privacy_policy': 'Privacy Policy',
      'pro': 'Pro',
      'pro_net_earning': 'Pro net earning',
      'professional': 'Professional',
      'profile': 'Profile',
      'profile_photo': 'Profile Photo',
      'profile_trust_message':
          'Keep your profile clear and professional to build trust with customers.',
      'profile_updated': 'Profile updated',
      'public_area_address': 'Public Area Address',
      'public_area_address_helper':
          'This is visible before acceptance (e.g., Sector G-11, Islamabad).',
      'push_notifications': 'Push Notifications',
      'push_notifications_desc':
          'Receive real-time jobs, bids, status and payment alerts',
      'pros_around_you': 'professionals around you',
      'send_test_notification': 'Send Test Notification',
      'send_test_notification_desc':
          'Preview how a worker gets a new job alert.',
      'test_notification_sent': 'Test notification sent.',
      'notification_permission_denied':
          'Notification permission was denied. Please allow it in device settings.',
      'raise_dispute': 'Raise Dispute',
      'rating': 'Rating',
      'record_cash_payment': 'Record Cash Payment',
      'register': 'Register',
      'register_subtitle_customer':
          'Create an account to book trusted local experts.',
      'register_subtitle_pro':
          'Join as a professional and receive nearby requests instantly.',
      'registration_form': 'Registration Form',
      'remove_photo': 'Remove Photo',
      'required_field': 'Required',
      'retry': 'Retry',
      'save': 'Save',
      'save_profile_changes': 'Save Profile Changes',
      'send_bid': 'Send Bid',
      'service_category': 'Service Category',
      'settings': 'Settings',
      'settings_subtitle': 'Language, privacy and notification preferences',
      'show_map': 'Show map',
      'hide_map': 'Hide map',
      'sign_out_subtitle': 'Sign out from this account',
      'status': 'Status',
      'status_available': 'Available',
      'status_cancelled': 'Cancelled',
      'status_completed': 'Completed',
      'status_disputed': 'Disputed',
      'status_in_process': 'In Process',
      'status_paid_closed': 'Paid & Closed',
      'status_posted': 'Posted',
      'take_picture': 'Take Picture',
      'tap_profile_photo_hint':
          'Tap your profile photo above to upload from gallery or take a picture.',
      'terms': 'Terms',
      'terms_acceptance_records': 'Terms acceptance records',
      'terms_conditions': 'Terms & Conditions',
      'terms_content':
          'By creating an account, you agree to provide accurate information, use lawful services, and respect marketplace rules. Job states, disputes, cancellations, payments, and verification events are auditable and recorded for trust and legal compliance.',
      'terms_privacy_required': 'Please accept Terms & Conditions.',
      'terms_records': 'Terms Records',
      'this_month': 'This Month',
      'timeline_audit_trail': 'Timeline & Audit Trail',
      'timeline_subtitle':
          'Every state/action is time-stamped and permanently logged',
      'today': 'Today',
      'type_message': 'Type your message',
      'update': 'Update',
      'upload_from_gallery': 'Upload from Gallery',
      'urdu': 'Urdu',
      'user_raised_dispute': 'User raised dispute',
      'user_requested_cancellation': 'User requested cancellation',
      'verification': 'Verification',
      'verified': 'Verified',
      'your_pending_jobs': 'Your pending jobs',
      'requests_loading': 'Loading requests',
      'your_bid_amount': 'Your bid amount',
      'your_location': 'Your location',
    },
    'ur': <String, String>{
      'accept': 'قبول کریں',
      'accept_terms': 'میں شرائط و ضوابط سے اتفاق کرتا/کرتی ہوں',
      'account_details': 'اکاؤنٹ کی تفصیلات',
      'account_trust_status': 'اکاؤنٹ اعتماد کی حالت',
      'account_type': 'اکاؤنٹ کی قسم',
      'actions': 'اقدامات',
      'actor': 'کارروائی کرنے والا',
      'address': 'پتہ',
      'admin': 'ایڈمن',
      'already_have_account_login': 'اکاؤنٹ پہلے سے موجود ہے؟ لاگ اِن کریں',
      'app_name': 'پاک سروس مارکیٹ پلیس',
      'auth_intro_subtitle':
          'پاکستان کے لیے قابلِ اعتماد مقامی سروسز۔ تیز بکنگ، تصدیق شدہ پروفیشنلز اور شفاف ادائیگیاں۔',
      'auth_point_audit': 'مکمل ٹائم لائن اور آڈٹ لاگنگ',
      'auth_point_identity_trust': 'شناخت اور اعتماد پر مبنی آن بورڈنگ',
      'auth_point_legal_acceptance': 'قانونی شرائط کی لازمی منظوری اور ریکارڈ',
      'auth_point_nearby_map': 'قریب کی جابز کے لیے لائیو نقشہ دریافت',
      'auth_point_payments': 'آن لائن اور نقد ادائیگی کا مکمل ریکارڈ',
      'auth_point_privacy_address': 'پرائیویسی محفوظ پتہ ہینڈلنگ',
      'auth_point_verified_pros': 'ریٹنگ اور ریویوز کے ساتھ تصدیق شدہ پروز',
      'bid_accepted': 'قبول شدہ',
      'bid_category_restricted':
          'اس زمرے کے رجسٹرڈ پروفیشنلز ہی بولی لگا سکتے ہیں۔',
      'bid_not_eligible': 'آپ اس جاب پر بولی لگانے کے لیے اہل نہیں ہیں۔',
      'bid_pending': 'زیرِ التوا',
      'bid_rejected': 'مسترد',
      'bid_submitted': 'بولی جمع ہو گئی',
      'bid_withdrawn': 'واپس لی گئی',
      'camera_permission_required':
          'پروفائل تصویر لینے کے لیے کیمرہ اجازت ضروری ہے۔',
      'cancel': 'منسوخ کریں',
      'cancel_job': 'جاب منسوخ کریں',
      'cancel_or_dispute': 'منسوخی یا تنازع اٹھائیں',
      'cancellation_disputes': 'منسوخی اور تنازعات',
      'cancellation_disputes_desc':
          'سروس شروع ہونے تک منسوخی کی اجازت ہے۔ تنازعات ٹائم لائن شواہد کے ساتھ لاگ ہوتے ہیں اور ایڈمن سنبھالتا ہے۔',
      'cancellation_reason': 'منسوخی کی وجہ',
      'cash': 'نقد',
      'category_ac_repair': 'اے سی مرمت',
      'category_appliance_repair': 'آلات کی مرمت',
      'category_carpenter': 'بڑھئی',
      'category_cleaning': 'صفائی',
      'category_electrician': 'الیکٹریشن',
      'category_registered_nurse': 'رجسٹرڈ نرس',
      'category_painter': 'پینٹر',
      'category_plumbing': 'پلمبنگ',
      'change_password': 'پاس ورڈ تبدیل کریں',
      'change_password_subtitle': 'اپنے اکاؤنٹ کی سیکیورٹی معلومات اپڈیٹ کریں',
      'change_profile_photo': 'پروفائل تصویر تبدیل کریں',
      'chat': 'چیٹ',
      'inbox_title': 'پیغامات',
      'inbox_subtitle': 'حالیہ گفتگو پہلے',
      'inbox_search_assigned': 'نام یا کام کے ذریعے تفویض شدہ گفتگو تلاش کریں',
      'inbox_recent_chats': 'حالیہ گفتگو',
      'inbox_empty':
          'ابھی کوئی گفتگو نہیں۔ کام پر گفتگو شروع ہونے کے بعد وہ یہاں نظر آئے گی۔',
      'choose_photo_source': 'تصویر اپڈیٹ کرنے کا طریقہ منتخب کریں۔',
      'cnic_pending': 'شناختی کارڈ زیرِ التوا',
      'cnic_verified': 'شناختی کارڈ تصدیق شدہ',
      'completed_jobs': 'مکمل جابز',
      'confirm_password': 'پاس ورڈ کی تصدیق',
      'create_account': 'اپنا اکاؤنٹ بنائیں',
      'current_password': 'موجودہ پاس ورڈ',
      'customer': 'کسٹمر',
      'demo_accounts': 'ڈیمو اکاؤنٹس:',
      'demo_admin_creds': 'ایڈمن: admin@pakservice.pk / Admin123!',
      'demo_customer_creds': 'کسٹمر: user@pakservice.pk / User12345!',
      'demo_pro_creds': 'Pro: pro@pakservice.pk / Pro12345!',
      'demo_locked_pro_creds':
          'Locked Pro: prolocked@pakservice.pk / Locked123!',
      'description': 'تفصیل',
      'discover': 'دریافت',
      'dispute_reason': 'تنازع کی وجہ',
      'earnings': 'کمائی',
      'earnings_dashboard': 'کمائی ڈیش بورڈ',
      'email': 'ای میل',
      'email_required': 'ای میل ضروری ہے',
      'english': 'انگریزی',
      'enter_to_accept': 'قبول کرنے کے لیے درج کریں:',
      'enter_valid_amount': 'درست رقم درج کریں',
      'exact_address': 'مکمل پتہ',
      'exact_address_helper': 'صرف پرو منتخب ہونے کے بعد دکھایا جائے گا۔',
      'exact_address_reveal_after_accept':
          'جاب قبول ہونے کے بعد مکمل پتہ ظاہر کیا جائے گا۔',
      'fee': 'فیس',
      'fixed_price': 'مقررہ قیمت (PKR)',
      'full_name': 'پورا نام',
      'gallery_permission_required':
          'پروفائل تصویر اپلوڈ کرنے کے لیے گیلری کی اجازت ضروری ہے۔',
      'gross': 'کل رقم',
      'help_support': 'مدد اور سپورٹ',
      'help_support_desc': 'فوری مدد کے لیے: support@pakservice.pk',
      'history': 'ہسٹری',
      'home': 'ہوم',
      'image_read_error':
          'منتخب تصویر پڑھی نہیں جا سکی، براہ کرم دوبارہ کوشش کریں۔',
      'job_detail': 'جاب کی تفصیل',
      'job_history': 'جاب ہسٹری',
      'job_not_found': 'جاب نہیں ملی',
      'job_payment_history': 'جاب اور ادائیگی کی ہسٹری',
      'job_payment_history_subtitle':
          'اپنی مکمل جابز، لین دین اور اسٹیٹس ٹائم لائن دیکھیں',
      'job_request': 'درخواست',
      'job_requests': 'درخواستیں',
      'job_posted_success':
          'جاب پوسٹ ہو گئی ہے اور قریبی پروز کے لیے دستیاب ہے۔',
      'job_title': 'جاب کا عنوان',
      'jobs': 'جابز',
      'jobs_around_you': 'آپ کے آس پاس جابز',
      'language': 'زبان',
      'lifetime': 'مجموعی',
      'linked_payment_account': 'منسلک ادائیگی اکاؤنٹ',
      'live': 'لائیو',
      'location_services_disabled':
          'لوکیشن سروسز بند ہیں۔ براہ کرم GPS آن کریں۔',
      'location_timeout': 'لوکیشن حاصل نہیں ہو سکی۔ دوبارہ کوشش کریں۔',
      'location_unavailable': 'لوکیشن دستیاب نہیں۔ دوبارہ کوشش کریں۔',
      'location_permission_nearby':
          'قریبی جابز دکھانے کے لیے لوکیشن اجازت ضروری ہے۔',
      'location_permission_post_job':
          'جاب پوسٹ کرنے کے لیے لوکیشن اجازت ضروری ہے۔',
      'login': 'لاگ اِن',
      'login_welcome_back': 'خوش آمدید، اپنے اکاؤنٹ سے جاری رکھیں۔',
      'logout': 'لاگ آؤٹ',
      'map_off_saving': 'بیٹری بچانے کے لیے نقشہ بند ہے۔',
      'mark_completed': 'مکمل نشان زد کریں',
      'method_cash': 'نقد',
      'method_easypaisa': 'ایزی پیسہ',
      'method_jazzcash': 'جاز کیش',
      'min_chars_6': 'کم از کم 6 حروف',
      'my_jobs': 'میری جابز',
      'nearby': 'قریب',
      'nearby_header_subtitle':
          'اپنے علاقے کی تصدیق شدہ درخواستیں دیکھیں اور فوراً بولی لگائیں۔',
      'nearby_jobs': 'قریبی جابز',
      'nearby_pros': 'Nearby Professionals',
      'nearby_pros_subtitle':
          'Find verified professionals around you by category.',
      'nearby_service_jobs': 'قریبی سروس جابز',
      'net': 'خالص',
      'new_password': 'نیا پاس ورڈ',
      'no_bids_received': 'ابھی تک کوئی بولی موصول نہیں ہوئی۔',
      'no_jobs_yet': 'ابھی کوئی جاب نہیں۔',
      'no_messages_yet': 'ابھی کوئی پیغام نہیں۔',
      'no_nearby_jobs':
          'ابھی قریب کوئی جاب نہیں۔ جگہ تبدیل کریں یا دوسری کیٹیگری آزمائیں۔',
      'no_nearby_pros': 'No nearby professionals found for this category yet.',
      'no_payment_records': 'ابھی ادائیگی کا کوئی ریکارڈ نہیں۔',
      'not_authenticated': 'تصدیق نہیں ہوئی',
      'not_logged_in': 'لاگ اِن نہیں',
      'notifications': 'اطلاعات',
      'online': 'آن لائن',
      'open_chat': 'چیٹ کھولیں',
      'open_chat_subtitle': 'دوسری پارٹی کے ساتھ حقیقی وقت چیٹ',
      'optional': 'اختیاری',
      'password': 'پاس ورڈ',
      'password_mismatch': 'پاس ورڈ اور تصدیقی پاس ورڈ ایک جیسے نہیں ہیں۔',
      'password_updated': 'پاس ورڈ اپڈیٹ ہو گیا',
      'pay_now': 'ابھی ادائیگی کریں',
      'pay_online_instant_payout':
          'آن لائن ادائیگی کریں اور فوری پرو پے آؤٹ دیں',
      'payment_account_helper':
          'فوری آن لائن ادائیگی کے لیے JazzCash یا Easypaisa اکاؤنٹ',
      'payment_completed': 'مکمل',
      'payment_failed': 'ناکام',
      'payment_initiated': 'شروع',
      'payment_recorded_closed': 'ادائیگی ریکارڈ ہو گئی اور جاب بند ہو گئی',
      'payment_records': 'ادائیگی کا ریکارڈ',
      'payment_summary': 'ادائیگی کا خلاصہ',
      'payments': 'ادائیگیاں',
      'pending': 'زیرِ التوا',
      'phone': 'فون نمبر',
      'platform_fee': 'پلیٹ فارم فیس (7.5%)',
      'platform_fees': 'پلیٹ فارم فیس',
      'police_badge': 'پولیس بیج',
      'police_badge_optional': 'پولیس بیج اختیاری',
      'post': 'پوسٹ',
      'post_job': 'جاب پوسٹ کریں',
      'post_new_job': 'نئی جاب پوسٹ کریں',
      'posted': 'پوسٹ کی گئی',
      'preferred_categories': 'پسندیدہ کیٹیگریز',
      'price': 'قیمت',
      'privacy': 'پرائیویسی',
      'privacy_content':
          'ہم سروس کو محفوظ طریقے سے چلانے کے لیے پروفائل، لوکیشن، کمیونیکیشن، ادائیگی اور آڈٹ میٹا ڈیٹا جمع کرتے ہیں۔ مکمل پتہ اسائنمنٹ سے پہلے ظاہر نہیں کیا جاتا۔ شرائط قبولیت میں وقت، ورژن، IP/ڈیوائس معلومات اور تصدیقی فلیگ محفوظ کیا جاتا ہے۔',
      'privacy_controls': 'پرائیویسی کنٹرولز',
      'privacy_controls_desc':
          'لوکیشن قریبی دریافت اور نیویگیشن کے لیے استعمال ہوتی ہے۔ مکمل پتہ دکھانا رول اور اسٹیٹ کے مطابق کنٹرول ہوتا ہے۔',
      'privacy_mode': 'پرائیویسی موڈ',
      'privacy_mode_desc': 'اسائنمنٹ سے پہلے مکمل پتہ چھپائیں',
      'privacy_policy': 'پرائیویسی پالیسی',
      'pro': 'پرو',
      'pro_net_earning': 'پرو کی خالص کمائی',
      'professional': 'پروفیشنل',
      'profile': 'پروفائل',
      'profile_photo': 'پروفائل تصویر',
      'profile_trust_message':
          'صارفین کا اعتماد بنانے کے لیے اپنا پروفائل واضح اور پیشہ ورانہ رکھیں۔',
      'profile_updated': 'پروفائل اپڈیٹ ہو گیا',
      'public_area_address': 'علاقے کا عمومی پتہ',
      'public_area_address_helper':
          'یہ قبولیت سے پہلے نظر آئے گا (مثلاً سیکٹر G-11، اسلام آباد)۔',
      'push_notifications': 'پش نوٹیفکیشنز',
      'push_notifications_desc':
          'جابز، بولی، اسٹیٹس اور ادائیگی کی فوری اطلاعات حاصل کریں',
      'pros_around_you': 'professionals around you',
      'notification_permission_denied':
          'نوٹیفکیشن کی اجازت مسترد ہو گئی۔ براہ کرم ڈیوائس سیٹنگز میں اجازت دیں۔',
      'raise_dispute': 'تنازع اٹھائیں',
      'rating': 'ریٹنگ',
      'record_cash_payment': 'نقد ادائیگی ریکارڈ کریں',
      'register': 'رجسٹر',
      'register_subtitle_customer':
          'قابلِ اعتماد مقامی ماہرین کی بکنگ کے لیے اکاؤنٹ بنائیں۔',
      'register_subtitle_pro':
          'پروفیشنل کے طور پر شامل ہوں اور فوراً قریبی درخواستیں حاصل کریں۔',
      'registration_form': 'رجسٹریشن فارم',
      'remove_photo': 'تصویر ہٹائیں',
      'required_field': 'ضروری',
      'retry': 'دوبارہ کوشش کریں',
      'save': 'محفوظ کریں',
      'save_profile_changes': 'پروفائل تبدیلیاں محفوظ کریں',
      'send_bid': 'بولی بھیجیں',
      'service_category': 'سروس کیٹیگری',
      'settings': 'ترتیبات',
      'settings_subtitle': 'زبان، پرائیویسی اور نوٹیفکیشن ترجیحات',
      'show_map': 'نقشہ دکھائیں',
      'hide_map': 'نقشہ چھپائیں',
      'sign_out_subtitle': 'اس اکاؤنٹ سے سائن آؤٹ کریں',
      'status': 'اسٹیٹس',
      'status_available': 'دستیاب',
      'status_cancelled': 'منسوخ',
      'status_completed': 'مکمل',
      'status_disputed': 'متنازع',
      'status_in_process': 'عمل جاری',
      'status_paid_closed': 'ادا شدہ اور بند',
      'status_posted': 'پوسٹ کی گئی',
      'take_picture': 'تصویر لیں',
      'tap_profile_photo_hint':
          'گیلری یا کیمرہ کے لیے اوپر پروفائل تصویر پر ٹیپ کریں۔',
      'terms': 'شرائط',
      'terms_acceptance_records': 'شرائط قبولیت کے ریکارڈ',
      'terms_conditions': 'شرائط و ضوابط',
      'terms_content':
          'اکاؤنٹ بنانے سے آپ درست معلومات فراہم کرنے، قانونی خدمات استعمال کرنے اور مارکیٹ پلیس قواعد کی پابندی پر متفق ہوتے ہیں۔ جاب اسٹیٹس، تنازعات، منسوخیاں، ادائیگیاں اور تصدیقی واقعات اعتماد اور قانونی تعمیل کے لیے آڈٹ ایبل طور پر ریکارڈ کیے جاتے ہیں۔',
      'terms_privacy_required': 'براہ کرم شرائط و ضوابط قبول کریں۔',
      'terms_records': 'شرائط کے ریکارڈ',
      'this_month': 'اس ماہ',
      'timeline_audit_trail': 'ٹائم لائن اور آڈٹ ٹریل',
      'timeline_subtitle':
          'ہر اسٹیٹ/عمل وقت کے ساتھ مستقل طور پر ریکارڈ ہوتا ہے',
      'today': 'آج',
      'type_message': 'اپنا پیغام لکھیں',
      'update': 'اپڈیٹ',
      'upload_from_gallery': 'گیلری سے اپلوڈ کریں',
      'urdu': 'اردو',
      'user_raised_dispute': 'صارف نے تنازع اٹھایا',
      'user_requested_cancellation': 'صارف نے منسوخی کی درخواست کی',
      'verification': 'تصدیق',
      'verified': 'تصدیق شدہ',
      'your_pending_jobs': 'آپ کی زیرِ التوا جابز',
      'requests_loading': 'درخواستیں لوڈ ہو رہی ہیں',
      'your_bid_amount': 'آپ کی بولی کی رقم',
      'your_location': 'آپ کی لوکیشن',
    },
  };

  String categoryLabel(String value) {
    return switch (value) {
      'plumbing' => t('category_plumbing'),
      'electrician' => t('category_electrician'),
      'ac_repair' => t('category_ac_repair'),
      'carpenter' => t('category_carpenter'),
      'painter' => t('category_painter'),
      'cleaning' => t('category_cleaning'),
      'appliance_repair' => t('category_appliance_repair'),
      'registered_nurse' => t('category_registered_nurse'),
      'handyman' => t('category_registered_nurse'),
      _ => value,
    };
  }

  String jobStatusLabel(String value) {
    return switch (value) {
      'posted' => t('status_posted'),
      'available' => t('status_available'),
      'in_process' => t('status_in_process'),
      'completed' => t('status_completed'),
      'paid_closed' => t('status_paid_closed'),
      'cancelled' => t('status_cancelled'),
      'disputed' => t('status_disputed'),
      _ => value,
    };
  }

  String bidStatusLabel(String value) {
    return switch (value) {
      'pending' => t('bid_pending'),
      'accepted' => t('bid_accepted'),
      'rejected' => t('bid_rejected'),
      'withdrawn' => t('bid_withdrawn'),
      _ => value,
    };
  }

  String paymentMethodLabel(String value) {
    return switch (value) {
      'jazzcash' => t('method_jazzcash'),
      'easypaisa' => t('method_easypaisa'),
      'cash' => t('method_cash'),
      _ => value,
    };
  }

  String paymentStateLabel(String value) {
    return switch (value) {
      'initiated' => t('payment_initiated'),
      'completed' => t('payment_completed'),
      'failed' => t('payment_failed'),
      _ => value,
    };
  }

  String t(String key) {
    final lang = _translations[locale.languageCode] ?? _translations['en']!;
    return lang[key] ?? _translations['en']![key] ?? key;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (l) => l.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
