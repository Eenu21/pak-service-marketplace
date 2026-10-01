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
      'accept': 'Ù‚Ø¨ÙˆÙ„ Ú©Ø±ÛŒÚº',
      'accept_terms':
          'Ù…ÛŒÚº Ø´Ø±Ø§Ø¦Ø· Ùˆ Ø¶ÙˆØ§Ø¨Ø· Ø³Û’ Ø§ØªÙØ§Ù‚ Ú©Ø±ØªØ§/Ú©Ø±ØªÛŒ ÛÙˆÚº',
      'account_details': 'Ø§Ú©Ø§Ø¤Ù†Ù¹ Ú©ÛŒ ØªÙØµÛŒÙ„Ø§Øª',
      'account_trust_status': 'Ø§Ú©Ø§Ø¤Ù†Ù¹ Ø§Ø¹ØªÙ…Ø§Ø¯ Ú©ÛŒ Ø­Ø§Ù„Øª',
      'account_type': 'Ø§Ú©Ø§Ø¤Ù†Ù¹ Ú©ÛŒ Ù‚Ø³Ù…',
      'actions': 'Ø§Ù‚Ø¯Ø§Ù…Ø§Øª',
      'actor': 'Ú©Ø§Ø±Ø±ÙˆØ§Ø¦ÛŒ Ú©Ø±Ù†Û’ ÙˆØ§Ù„Ø§',
      'address': 'Ù¾ØªÛ',
      'admin': 'Ø§ÛŒÚˆÙ…Ù†',
      'already_have_account_login':
          'Ø§Ú©Ø§Ø¤Ù†Ù¹ Ù¾ÛÙ„Û’ Ø³Û’ Ù…ÙˆØ¬ÙˆØ¯ ÛÛ’ØŸ Ù„Ø§Ú¯ Ø§ÙÙ† Ú©Ø±ÛŒÚº',
      'app_name': 'Ù¾Ø§Ú© Ø³Ø±ÙˆØ³ Ù…Ø§Ø±Ú©ÛŒÙ¹ Ù¾Ù„ÛŒØ³',
      'auth_intro_subtitle':
          'Ù¾Ø§Ú©Ø³ØªØ§Ù† Ú©Û’ Ù„ÛŒÛ’ Ù‚Ø§Ø¨Ù„Ù Ø§Ø¹ØªÙ…Ø§Ø¯ Ù…Ù‚Ø§Ù…ÛŒ Ø³Ø±ÙˆØ³Ø²Û” ØªÛŒØ² Ø¨Ú©Ù†Ú¯ØŒ ØªØµØ¯ÛŒÙ‚ Ø´Ø¯Û Ù¾Ø±ÙˆÙÛŒØ´Ù†Ù„Ø² Ø§ÙˆØ± Ø´ÙØ§Ù Ø§Ø¯Ø§Ø¦ÛŒÚ¯ÛŒØ§ÚºÛ”',
      'auth_point_audit': 'Ù…Ú©Ù…Ù„ Ù¹Ø§Ø¦Ù… Ù„Ø§Ø¦Ù† Ø§ÙˆØ± Ø¢ÚˆÙ¹ Ù„Ø§Ú¯Ù†Ú¯',
      'auth_point_identity_trust':
          'Ø´Ù†Ø§Ø®Øª Ø§ÙˆØ± Ø§Ø¹ØªÙ…Ø§Ø¯ Ù¾Ø± Ù…Ø¨Ù†ÛŒ Ø¢Ù† Ø¨ÙˆØ±ÚˆÙ†Ú¯',
      'auth_point_legal_acceptance':
          'Ù‚Ø§Ù†ÙˆÙ†ÛŒ Ø´Ø±Ø§Ø¦Ø· Ú©ÛŒ Ù„Ø§Ø²Ù…ÛŒ Ù…Ù†Ø¸ÙˆØ±ÛŒ Ø§ÙˆØ± Ø±ÛŒÚ©Ø§Ø±Úˆ',
      'auth_point_nearby_map':
          'Ù‚Ø±ÛŒØ¨ Ú©ÛŒ Ø¬Ø§Ø¨Ø² Ú©Û’ Ù„ÛŒÛ’ Ù„Ø§Ø¦ÛŒÙˆ Ù†Ù‚Ø´Û Ø¯Ø±ÛŒØ§ÙØª',
      'auth_point_payments':
          'Ø¢Ù† Ù„Ø§Ø¦Ù† Ø§ÙˆØ± Ù†Ù‚Ø¯ Ø§Ø¯Ø§Ø¦ÛŒÚ¯ÛŒ Ú©Ø§ Ù…Ú©Ù…Ù„ Ø±ÛŒÚ©Ø§Ø±Úˆ',
      'auth_point_privacy_address':
          'Ù¾Ø±Ø§Ø¦ÛŒÙˆÛŒØ³ÛŒ Ù…Ø­ÙÙˆØ¸ Ù¾ØªÛ ÛÛŒÙ†ÚˆÙ„Ù†Ú¯',
      'auth_point_verified_pros':
          'Ø±ÛŒÙ¹Ù†Ú¯ Ø§ÙˆØ± Ø±ÛŒÙˆÛŒÙˆØ² Ú©Û’ Ø³Ø§ØªÚ¾ ØªØµØ¯ÛŒÙ‚ Ø´Ø¯Û Ù¾Ø±ÙˆØ²',
      'bid_accepted': 'Ù‚Ø¨ÙˆÙ„ Ø´Ø¯Û',
      'bid_category_restricted':
          'Ø§Ø³ Ø²Ù…Ø±Û Ú©ÛŒ Ø±Ø¬Ø³Ù¹Ø±Úڈ Ø´Ø¯Û Ù¾Ø±ÙˆÙÛŒØ´Ù†Ù„Ø² ÛÛŒ Ø¨ÙˆÙ„ÛŒ Ù„Ú¯Ø§ Ø³Ú©ØªÛ’ ÛÛŒÚºÛ”',
      'bid_not_eligible':
          'Ø¢Ù¾ Ø§Ø³ Ø¬Ø§Ø¨ Ù¾Ø± Ø¨ÙˆÙ„ÛŒ Ù„Ú¯Ø§Ù†Û’ Ú©Û’ Ù„ÛŒÛ’ Ø§ÛÙ„ Ù†ÛÛŒÚº ÛÛŒÚºÛ”',
      'bid_pending': 'Ø²ÛŒØ±Ù Ø§Ù„ØªÙˆØ§',
      'bid_rejected': 'Ù…Ø³ØªØ±Ø¯',
      'bid_submitted': 'Ø¨ÙˆÙ„ÛŒ Ø¬Ù…Ø¹ ÛÙˆ Ú¯Ø¦ÛŒ',
      'bid_withdrawn': 'ÙˆØ§Ù¾Ø³ Ù„ÛŒ Ú¯Ø¦ÛŒ',
      'camera_permission_required':
          'Ù¾Ø±ÙˆÙØ§Ø¦Ù„ ØªØµÙˆÛŒØ± Ù„ÛŒÙ†Û’ Ú©Û’ Ù„ÛŒÛ’ Ú©ÛŒÙ…Ø±Û Ø§Ø¬Ø§Ø²Øª Ø¶Ø±ÙˆØ±ÛŒ ÛÛ’Û”',
      'cancel': 'Ù…Ù†Ø³ÙˆØ® Ú©Ø±ÛŒÚº',
      'cancel_job': 'Ø¬Ø§Ø¨ Ù…Ù†Ø³ÙˆØ® Ú©Ø±ÛŒÚº',
      'cancel_or_dispute': 'Ù…Ù†Ø³ÙˆØ®ÛŒ ÛŒØ§ ØªÙ†Ø§Ø²Ø¹ Ø§Ù¹Ú¾Ø§Ø¦ÛŒÚº',
      'cancellation_disputes': 'Ù…Ù†Ø³ÙˆØ®ÛŒ Ø§ÙˆØ± ØªÙ†Ø§Ø²Ø¹Ø§Øª',
      'cancellation_disputes_desc':
          'Ø³Ø±ÙˆØ³ Ø´Ø±ÙˆØ¹ ÛÙˆÙ†Û’ ØªÚ© Ù…Ù†Ø³ÙˆØ®ÛŒ Ú©ÛŒ Ø§Ø¬Ø§Ø²Øª ÛÛ’Û” ØªÙ†Ø§Ø²Ø¹Ø§Øª Ù¹Ø§Ø¦Ù… Ù„Ø§Ø¦Ù† Ø´ÙˆØ§ÛØ¯ Ú©Û’ Ø³Ø§ØªÚ¾ Ù„Ø§Ú¯ ÛÙˆØªÛ’ ÛÛŒÚº Ø§ÙˆØ± Ø§ÛŒÚˆÙ…Ù† Ø³Ù†Ø¨Ú¾Ø§Ù„ØªØ§ ÛÛ’Û”',
      'cancellation_reason': 'Ù…Ù†Ø³ÙˆØ®ÛŒ Ú©ÛŒ ÙˆØ¬Û',
      'cash': 'Ù†Ù‚Ø¯',
      'category_ac_repair': 'Ø§Û’ Ø³ÛŒ Ù…Ø±Ù…Øª',
      'category_appliance_repair': 'Ø¢Ù„Ø§Øª Ú©ÛŒ Ù…Ø±Ù…Øª',
      'category_carpenter': 'Ø¨Ú‘Ú¾Ø¦ÛŒ',
      'category_cleaning': 'ØµÙØ§Ø¦ÛŒ',
      'category_electrician': 'Ø§Ù„ÛŒÚ©Ù¹Ø±ÛŒØ´Ù†',
      'category_registered_nurse': 'Ø±Ø¬Ø³Ù¹Ø±Úˆ Ù†Ø±Ø³',
      'category_painter': 'Ù¾ÛŒÙ†Ù¹Ø±',
      'category_plumbing': 'Ù¾Ù„Ù…Ø¨Ù†Ú¯',
      'change_password': 'Ù¾Ø§Ø³ ÙˆØ±Úˆ ØªØ¨Ø¯ÛŒÙ„ Ú©Ø±ÛŒÚº',
      'change_password_subtitle':
          'Ø§Ù¾Ù†Û’ Ø§Ú©Ø§Ø¤Ù†Ù¹ Ú©ÛŒ Ø³ÛŒÚ©ÛŒÙˆØ±Ù¹ÛŒ Ù…Ø¹Ù„ÙˆÙ…Ø§Øª Ø§Ù¾ÚˆÛŒÙ¹ Ú©Ø±ÛŒÚº',
      'change_profile_photo': 'Ù¾Ø±ÙˆÙØ§Ø¦Ù„ ØªØµÙˆÛŒØ± ØªØ¨Ø¯ÛŒÙ„ Ú©Ø±ÛŒÚº',
      'chat': 'Ú†ÛŒÙ¹',
      'choose_photo_source':
          'ØªØµÙˆÛŒØ± Ø§Ù¾ÚˆÛŒÙ¹ Ú©Ø±Ù†Û’ Ú©Ø§ Ø·Ø±ÛŒÙ‚Û Ù…Ù†ØªØ®Ø¨ Ú©Ø±ÛŒÚºÛ”',
      'cnic_pending': 'Ø´Ù†Ø§Ø®ØªÛŒ Ú©Ø§Ø±Úˆ Ø²ÛŒØ±Ù Ø§Ù„ØªÙˆØ§',
      'cnic_verified': 'Ø´Ù†Ø§Ø®ØªÛŒ Ú©Ø§Ø±Úˆ ØªØµØ¯ÛŒÙ‚ Ø´Ø¯Û',
      'completed_jobs': 'Ù…Ú©Ù…Ù„ Ø¬Ø§Ø¨Ø²',
      'confirm_password': 'Ù¾Ø§Ø³ ÙˆØ±Úˆ Ú©ÛŒ ØªØµØ¯ÛŒÙ‚',
      'create_account': 'Ø§Ù¾Ù†Ø§ Ø§Ú©Ø§Ø¤Ù†Ù¹ Ø¨Ù†Ø§Ø¦ÛŒÚº',
      'current_password': 'Ù…ÙˆØ¬ÙˆØ¯Û Ù¾Ø§Ø³ ÙˆØ±Úˆ',
      'customer': 'Ú©Ø³Ù¹Ù…Ø±',
      'demo_accounts': 'ÚˆÛŒÙ…Ùˆ Ø§Ú©Ø§Ø¤Ù†Ù¹Ø³:',
      'demo_admin_creds': 'Ø§ÛŒÚˆÙ…Ù†: admin@pakservice.pk / Admin123!',
      'demo_customer_creds': 'Ú©Ø³Ù¹Ù…Ø±: user@pakservice.pk / User12345!',
      'demo_pro_creds': 'Pro: pro@pakservice.pk / Pro12345!',
      'demo_locked_pro_creds':
          'Locked Pro: prolocked@pakservice.pk / Locked123!',
      'description': 'ØªÙØµÛŒÙ„',
      'discover': 'Ø¯Ø±ÛŒØ§ÙØª',
      'dispute_reason': 'ØªÙ†Ø§Ø²Ø¹ Ú©ÛŒ ÙˆØ¬Û',
      'earnings': 'Ú©Ù…Ø§Ø¦ÛŒ',
      'earnings_dashboard': 'Ú©Ù…Ø§Ø¦ÛŒ ÚˆÛŒØ´ Ø¨ÙˆØ±Úˆ',
      'email': 'Ø§ÛŒ Ù…ÛŒÙ„',
      'email_required': 'Ø§ÛŒ Ù…ÛŒÙ„ Ø¶Ø±ÙˆØ±ÛŒ ÛÛ’',
      'english': 'Ø§Ù†Ú¯Ø±ÛŒØ²ÛŒ',
      'enter_to_accept': 'Ù‚Ø¨ÙˆÙ„ Ú©Ø±Ù†Û’ Ú©Û’ Ù„ÛŒÛ’ Ø¯Ø±Ø¬ Ú©Ø±ÛŒÚº:',
      'enter_valid_amount': 'Ø¯Ø±Ø³Øª Ø±Ù‚Ù… Ø¯Ø±Ø¬ Ú©Ø±ÛŒÚº',
      'exact_address': 'Ù…Ú©Ù…Ù„ Ù¾ØªÛ',
      'exact_address_helper':
          'ØµØ±Ù Ù¾Ø±Ùˆ Ù…Ù†ØªØ®Ø¨ ÛÙˆÙ†Û’ Ú©Û’ Ø¨Ø¹Ø¯ Ø¯Ú©Ú¾Ø§ÛŒØ§ Ø¬Ø§Ø¦Û’ Ú¯Ø§Û”',
      'exact_address_reveal_after_accept':
          'Ø¬Ø§Ø¨ Ù‚Ø¨ÙˆÙ„ ÛÙˆÙ†Û’ Ú©Û’ Ø¨Ø¹Ø¯ Ù…Ú©Ù…Ù„ Ù¾ØªÛ Ø¸Ø§ÛØ± Ú©ÛŒØ§ Ø¬Ø§Ø¦Û’ Ú¯Ø§Û”',
      'fee': 'ÙÛŒØ³',
      'fixed_price': 'Ù…Ù‚Ø±Ø±Û Ù‚ÛŒÙ…Øª (PKR)',
      'full_name': 'Ù¾ÙˆØ±Ø§ Ù†Ø§Ù…',
      'gallery_permission_required':
          'Ù¾Ø±ÙˆÙØ§Ø¦Ù„ ØªØµÙˆÛŒØ± Ø§Ù¾Ù„ÙˆÚˆ Ú©Ø±Ù†Û’ Ú©Û’ Ù„ÛŒÛ’ Ú¯ÛŒÙ„Ø±ÛŒ Ú©ÛŒ Ø§Ø¬Ø§Ø²Øª Ø¶Ø±ÙˆØ±ÛŒ ÛÛ’Û”',
      'gross': 'Ú©Ù„ Ø±Ù‚Ù…',
      'help_support': 'Ù…Ø¯Ø¯ Ø§ÙˆØ± Ø³Ù¾ÙˆØ±Ù¹',
      'help_support_desc': 'ÙÙˆØ±ÛŒ Ù…Ø¯Ø¯ Ú©Û’ Ù„ÛŒÛ’: support@pakservice.pk',
      'history': 'ÛØ³Ù¹Ø±ÛŒ',
      'home': 'ÛÙˆÙ…',
      'image_read_error':
          'Ù…Ù†ØªØ®Ø¨ ØªØµÙˆÛŒØ± Ù¾Ú‘Ú¾ÛŒ Ù†ÛÛŒÚº Ø¬Ø§ Ø³Ú©ÛŒØŒ Ø¨Ø±Ø§Û Ú©Ø±Ù… Ø¯ÙˆØ¨Ø§Ø±Û Ú©ÙˆØ´Ø´ Ú©Ø±ÛŒÚºÛ”',
      'job_detail': 'Ø¬Ø§Ø¨ Ú©ÛŒ ØªÙØµÛŒÙ„',
      'job_history': 'Ø¬Ø§Ø¨ ÛØ³Ù¹Ø±ÛŒ',
      'job_not_found': 'Ø¬Ø§Ø¨ Ù†ÛÛŒÚº Ù…Ù„ÛŒ',
      'job_payment_history': 'Ø¬Ø§Ø¨ Ø§ÙˆØ± Ø§Ø¯Ø§Ø¦ÛŒÚ¯ÛŒ Ú©ÛŒ ÛØ³Ù¹Ø±ÛŒ',
      'job_payment_history_subtitle':
          'Ø§Ù¾Ù†ÛŒ Ù…Ú©Ù…Ù„ Ø¬Ø§Ø¨Ø²ØŒ Ù„ÛŒÙ† Ø¯ÛŒÙ† Ø§ÙˆØ± Ø§Ø³Ù¹ÛŒÙ¹Ø³ Ù¹Ø§Ø¦Ù… Ù„Ø§Ø¦Ù† Ø¯ÛŒÚ©Ú¾ÛŒÚº',
      'job_request': 'Ø¯Ø±Ø®ÙˆØ§Ø³Øª',
      'job_requests': 'Ø¯Ø±Ø®ÙˆØ§Ø³ØªÛŒÚº',
      'job_posted_success':
          'Ø¬Ø§Ø¨ Ù¾ÙˆØ³Ù¹ ÛÙˆ Ú¯Ø¦ÛŒ ÛÛ’ Ø§ÙˆØ± Ù‚Ø±ÛŒØ¨ÛŒ Ù¾Ø±ÙˆØ² Ú©Û’ Ù„ÛŒÛ’ Ø¯Ø³ØªÛŒØ§Ø¨ ÛÛ’Û”',
      'job_title': 'Ø¬Ø§Ø¨ Ú©Ø§ Ø¹Ù†ÙˆØ§Ù†',
      'jobs': 'Ø¬Ø§Ø¨Ø²',
      'jobs_around_you': 'Ø¢Ù¾ Ú©Û’ Ø¢Ø³ Ù¾Ø§Ø³ Ø¬Ø§Ø¨Ø²',
      'language': 'Ø²Ø¨Ø§Ù†',
      'lifetime': 'Ù…Ø¬Ù…ÙˆØ¹ÛŒ',
      'linked_payment_account': 'Ù…Ù†Ø³Ù„Ú© Ø§Ø¯Ø§Ø¦ÛŒÚ¯ÛŒ Ø§Ú©Ø§Ø¤Ù†Ù¹',
      'live': 'Ù„Ø§Ø¦ÛŒÙˆ',
      'location_services_disabled':
          'Ù„ÙˆÚ©ÛŒØ´Ù† Ø³Ø±ÙˆØ³Ø² Ø¨Ù†Ø¯ ÛÛŒÚºÛ” Ø¨Ø±Ø§Û Ú©Ø±Ù… GPS Ø¢Ù† Ú©Ø±ÛŒÚºÛ”',
      'location_timeout':
          'Ù„ÙˆÚ©ÛŒØ´Ù† Ø­Ø§ØµÙ„ Ù†ÛÛŒÚº ÛÙˆ Ø³Ú©ÛŒÛ” Ø¯ÙˆØ¨Ø§Ø±Û Ú©ÙˆØ´Ø´ Ú©Ø±ÛŒÚºÛ”',
      'location_unavailable':
          'Ù„ÙˆÚ©ÛŒØ´Ù† Ø¯Ø³ØªÛŒØ§Ø¨ Ù†ÛÛŒÚºÛ” Ø¯ÙˆØ¨Ø§Ø±Û Ú©ÙˆØ´Ø´ Ú©Ø±ÛŒÚºÛ”',
      'location_permission_nearby':
          'Ù‚Ø±ÛŒØ¨ÛŒ Ø¬Ø§Ø¨Ø² Ø¯Ú©Ú¾Ø§Ù†Û’ Ú©Û’ Ù„ÛŒÛ’ Ù„ÙˆÚ©ÛŒØ´Ù† Ø§Ø¬Ø§Ø²Øª Ø¶Ø±ÙˆØ±ÛŒ ÛÛ’Û”',
      'location_permission_post_job':
          'Ø¬Ø§Ø¨ Ù¾ÙˆØ³Ù¹ Ú©Ø±Ù†Û’ Ú©Û’ Ù„ÛŒÛ’ Ù„ÙˆÚ©ÛŒØ´Ù† Ø§Ø¬Ø§Ø²Øª Ø¶Ø±ÙˆØ±ÛŒ ÛÛ’Û”',
      'login': 'Ù„Ø§Ú¯ Ø§ÙÙ†',
      'login_welcome_back':
          'Ø®ÙˆØ´ Ø¢Ù…Ø¯ÛŒØ¯ØŒ Ø§Ù¾Ù†Û’ Ø§Ú©Ø§Ø¤Ù†Ù¹ Ø³Û’ Ø¬Ø§Ø±ÛŒ Ø±Ú©Ú¾ÛŒÚºÛ”',
      'logout': 'Ù„Ø§Ú¯ Ø¢Ø¤Ù¹',
      'map_off_saving':
          'Ø¨ÛŒÙ¹Ø±ÛŒ Ø¨Ú†Ø§Ù†Û’ Ú©Û’ Ù„ÛŒÛ’ Ù†Ù‚Ø´Û Ø¨Ù†Ø¯ ÛÛ’Û”',
      'mark_completed': 'Ù…Ú©Ù…Ù„ Ù†Ø´Ø§Ù† Ø²Ø¯ Ú©Ø±ÛŒÚº',
      'method_cash': 'Ù†Ù‚Ø¯',
      'method_easypaisa': 'Ø§ÛŒØ²ÛŒ Ù¾ÛŒØ³Û',
      'method_jazzcash': 'Ø¬Ø§Ø² Ú©ÛŒØ´',
      'min_chars_6': 'Ú©Ù… Ø§Ø² Ú©Ù… 6 Ø­Ø±ÙˆÙ',
      'my_jobs': 'Ù…ÛŒØ±ÛŒ Ø¬Ø§Ø¨Ø²',
      'nearby': 'Ù‚Ø±ÛŒØ¨',
      'nearby_header_subtitle':
          'Ø§Ù¾Ù†Û’ Ø¹Ù„Ø§Ù‚Û’ Ú©ÛŒ ØªØµØ¯ÛŒÙ‚ Ø´Ø¯Û Ø¯Ø±Ø®ÙˆØ§Ø³ØªÛŒÚº Ø¯ÛŒÚ©Ú¾ÛŒÚº Ø§ÙˆØ± ÙÙˆØ±Ø§Ù‹ Ø¨ÙˆÙ„ÛŒ Ù„Ú¯Ø§Ø¦ÛŒÚºÛ”',
      'nearby_jobs': 'Ù‚Ø±ÛŒØ¨ÛŒ Ø¬Ø§Ø¨Ø²',
      'nearby_pros': 'Nearby Professionals',
      'nearby_pros_subtitle':
          'Find verified professionals around you by category.',
      'nearby_service_jobs': 'Ù‚Ø±ÛŒØ¨ÛŒ Ø³Ø±ÙˆØ³ Ø¬Ø§Ø¨Ø²',
      'net': 'Ø®Ø§Ù„Øµ',
      'new_password': 'Ù†ÛŒØ§ Ù¾Ø§Ø³ ÙˆØ±Úˆ',
      'no_bids_received':
          'Ø§Ø¨Ú¾ÛŒ ØªÚ© Ú©ÙˆØ¦ÛŒ Ø¨ÙˆÙ„ÛŒ Ù…ÙˆØµÙˆÙ„ Ù†ÛÛŒÚº ÛÙˆØ¦ÛŒÛ”',
      'no_jobs_yet': 'Ø§Ø¨Ú¾ÛŒ Ú©ÙˆØ¦ÛŒ Ø¬Ø§Ø¨ Ù†ÛÛŒÚºÛ”',
      'no_messages_yet': 'Ø§Ø¨Ú¾ÛŒ Ú©ÙˆØ¦ÛŒ Ù¾ÛŒØºØ§Ù… Ù†ÛÛŒÚºÛ”',
      'no_nearby_jobs':
          'Ø§Ø¨Ú¾ÛŒ Ù‚Ø±ÛŒØ¨ Ú©ÙˆØ¦ÛŒ Ø¬Ø§Ø¨ Ù†ÛÛŒÚºÛ” Ø¬Ú¯Û ØªØ¨Ø¯ÛŒÙ„ Ú©Ø±ÛŒÚº ÛŒØ§ Ø¯ÙˆØ³Ø±ÛŒ Ú©ÛŒÙ¹ÛŒÚ¯Ø±ÛŒ Ø¢Ø²Ù…Ø§Ø¦ÛŒÚºÛ”',
      'no_nearby_pros': 'No nearby professionals found for this category yet.',
      'no_payment_records':
          'Ø§Ø¨Ú¾ÛŒ Ø§Ø¯Ø§Ø¦ÛŒÚ¯ÛŒ Ú©Ø§ Ú©ÙˆØ¦ÛŒ Ø±ÛŒÚ©Ø§Ø±Úˆ Ù†ÛÛŒÚºÛ”',
      'not_authenticated': 'ØªØµØ¯ÛŒÙ‚ Ù†ÛÛŒÚº ÛÙˆØ¦ÛŒ',
      'not_logged_in': 'Ù„Ø§Ú¯ Ø§ÙÙ† Ù†ÛÛŒÚº',
      'notifications': 'Ø§Ø·Ù„Ø§Ø¹Ø§Øª',
      'online': 'Ø¢Ù† Ù„Ø§Ø¦Ù†',
      'open_chat': 'Ú†ÛŒÙ¹ Ú©Ú¾ÙˆÙ„ÛŒÚº',
      'open_chat_subtitle':
          'Ø¯ÙˆØ³Ø±ÛŒ Ù¾Ø§Ø±Ù¹ÛŒ Ú©Û’ Ø³Ø§ØªÚ¾ Ø­Ù‚ÛŒÙ‚ÛŒ ÙˆÙ‚Øª Ú†ÛŒÙ¹',
      'optional': 'Ø§Ø®ØªÛŒØ§Ø±ÛŒ',
      'password': 'Ù¾Ø§Ø³ ÙˆØ±Úˆ',
      'password_mismatch':
          'Ù¾Ø§Ø³ ÙˆØ±Úˆ Ø§ÙˆØ± ØªØµØ¯ÛŒÙ‚ÛŒ Ù¾Ø§Ø³ ÙˆØ±Úˆ Ø§ÛŒÚ© Ø¬ÛŒØ³Û’ Ù†ÛÛŒÚº ÛÛŒÚºÛ”',
      'password_updated': 'Ù¾Ø§Ø³ ÙˆØ±Úˆ Ø§Ù¾ÚˆÛŒÙ¹ ÛÙˆ Ú¯ÛŒØ§',
      'pay_now': 'Ø§Ø¨Ú¾ÛŒ Ø§Ø¯Ø§Ø¦ÛŒÚ¯ÛŒ Ú©Ø±ÛŒÚº',
      'pay_online_instant_payout':
          'Ø¢Ù† Ù„Ø§Ø¦Ù† Ø§Ø¯Ø§Ø¦ÛŒÚ¯ÛŒ Ú©Ø±ÛŒÚº Ø§ÙˆØ± ÙÙˆØ±ÛŒ Ù¾Ø±Ùˆ Ù¾Û’ Ø¢Ø¤Ù¹ Ø¯ÛŒÚº',
      'payment_account_helper':
          'ÙÙˆØ±ÛŒ Ø¢Ù† Ù„Ø§Ø¦Ù† Ø§Ø¯Ø§Ø¦ÛŒÚ¯ÛŒ Ú©Û’ Ù„ÛŒÛ’ JazzCash ÛŒØ§ Easypaisa Ø§Ú©Ø§Ø¤Ù†Ù¹',
      'payment_completed': 'Ù…Ú©Ù…Ù„',
      'payment_failed': 'Ù†Ø§Ú©Ø§Ù…',
      'payment_initiated': 'Ø´Ø±ÙˆØ¹',
      'payment_recorded_closed':
          'Ø§Ø¯Ø§Ø¦ÛŒÚ¯ÛŒ Ø±ÛŒÚ©Ø§Ø±Úˆ ÛÙˆ Ú¯Ø¦ÛŒ Ø§ÙˆØ± Ø¬Ø§Ø¨ Ø¨Ù†Ø¯ ÛÙˆ Ú¯Ø¦ÛŒ',
      'payment_records': 'Ø§Ø¯Ø§Ø¦ÛŒÚ¯ÛŒ Ú©Ø§ Ø±ÛŒÚ©Ø§Ø±Úˆ',
      'payment_summary': 'Ø§Ø¯Ø§Ø¦ÛŒÚ¯ÛŒ Ú©Ø§ Ø®Ù„Ø§ØµÛ',
      'payments': 'Ø§Ø¯Ø§Ø¦ÛŒÚ¯ÛŒØ§Úº',
      'pending': 'Ø²ÛŒØ±Ù Ø§Ù„ØªÙˆØ§',
      'phone': 'ÙÙˆÙ† Ù†Ù…Ø¨Ø±',
      'platform_fee': 'Ù¾Ù„ÛŒÙ¹ ÙØ§Ø±Ù… ÙÛŒØ³ (7.5%)',
      'platform_fees': 'Ù¾Ù„ÛŒÙ¹ ÙØ§Ø±Ù… ÙÛŒØ³',
      'police_badge': 'Ù¾ÙˆÙ„ÛŒØ³ Ø¨ÛŒØ¬',
      'police_badge_optional': 'Ù¾ÙˆÙ„ÛŒØ³ Ø¨ÛŒØ¬ Ø§Ø®ØªÛŒØ§Ø±ÛŒ',
      'post': 'Ù¾ÙˆØ³Ù¹',
      'post_job': 'Ø¬Ø§Ø¨ Ù¾ÙˆØ³Ù¹ Ú©Ø±ÛŒÚº',
      'post_new_job': 'Ù†Ø¦ÛŒ Ø¬Ø§Ø¨ Ù¾ÙˆØ³Ù¹ Ú©Ø±ÛŒÚº',
      'posted': 'Ù¾ÙˆØ³Ù¹ Ú©ÛŒ Ú¯Ø¦ÛŒ',
      'preferred_categories': 'Ù¾Ø³Ù†Ø¯ÛŒØ¯Û Ú©ÛŒÙ¹ÛŒÚ¯Ø±ÛŒØ²',
      'price': 'Ù‚ÛŒÙ…Øª',
      'privacy': 'Ù¾Ø±Ø§Ø¦ÛŒÙˆÛŒØ³ÛŒ',
      'privacy_content':
          'ÛÙ… Ø³Ø±ÙˆØ³ Ú©Ùˆ Ù…Ø­ÙÙˆØ¸ Ø·Ø±ÛŒÙ‚Û’ Ø³Û’ Ú†Ù„Ø§Ù†Û’ Ú©Û’ Ù„ÛŒÛ’ Ù¾Ø±ÙˆÙØ§Ø¦Ù„ØŒ Ù„ÙˆÚ©ÛŒØ´Ù†ØŒ Ú©Ù…ÛŒÙˆÙ†ÛŒÚ©ÛŒØ´Ù†ØŒ Ø§Ø¯Ø§Ø¦ÛŒÚ¯ÛŒ Ø§ÙˆØ± Ø¢ÚˆÙ¹ Ù…ÛŒÙ¹Ø§ ÚˆÛŒÙ¹Ø§ Ø¬Ù…Ø¹ Ú©Ø±ØªÛ’ ÛÛŒÚºÛ” Ù…Ú©Ù…Ù„ Ù¾ØªÛ Ø§Ø³Ø§Ø¦Ù†Ù…Ù†Ù¹ Ø³Û’ Ù¾ÛÙ„Û’ Ø¸Ø§ÛØ± Ù†ÛÛŒÚº Ú©ÛŒØ§ Ø¬Ø§ØªØ§Û” Ø´Ø±Ø§Ø¦Ø· Ù‚Ø¨ÙˆÙ„ÛŒØª Ù…ÛŒÚº ÙˆÙ‚ØªØŒ ÙˆØ±Ú˜Ù†ØŒ IP/ÚˆÛŒÙˆØ§Ø¦Ø³ Ù…Ø¹Ù„ÙˆÙ…Ø§Øª Ø§ÙˆØ± ØªØµØ¯ÛŒÙ‚ÛŒ ÙÙ„ÛŒÚ¯ Ù…Ø­ÙÙˆØ¸ Ú©ÛŒØ§ Ø¬Ø§ØªØ§ ÛÛ’Û”',
      'privacy_controls': 'Ù¾Ø±Ø§Ø¦ÛŒÙˆÛŒØ³ÛŒ Ú©Ù†Ù¹Ø±ÙˆÙ„Ø²',
      'privacy_controls_desc':
          'Ù„ÙˆÚ©ÛŒØ´Ù† Ù‚Ø±ÛŒØ¨ÛŒ Ø¯Ø±ÛŒØ§ÙØª Ø§ÙˆØ± Ù†ÛŒÙˆÛŒÚ¯ÛŒØ´Ù† Ú©Û’ Ù„ÛŒÛ’ Ø§Ø³ØªØ¹Ù…Ø§Ù„ ÛÙˆØªÛŒ ÛÛ’Û” Ù…Ú©Ù…Ù„ Ù¾ØªÛ Ø¯Ú©Ú¾Ø§Ù†Ø§ Ø±ÙˆÙ„ Ø§ÙˆØ± Ø§Ø³Ù¹ÛŒÙ¹ Ú©Û’ Ù…Ø·Ø§Ø¨Ù‚ Ú©Ù†Ù¹Ø±ÙˆÙ„ ÛÙˆØªØ§ ÛÛ’Û”',
      'privacy_mode': 'Ù¾Ø±Ø§Ø¦ÛŒÙˆÛŒØ³ÛŒ Ù…ÙˆÚˆ',
      'privacy_mode_desc':
          'Ø§Ø³Ø§Ø¦Ù†Ù…Ù†Ù¹ Ø³Û’ Ù¾ÛÙ„Û’ Ù…Ú©Ù…Ù„ Ù¾ØªÛ Ú†Ú¾Ù¾Ø§Ø¦ÛŒÚº',
      'privacy_policy': 'Ù¾Ø±Ø§Ø¦ÛŒÙˆÛŒØ³ÛŒ Ù¾Ø§Ù„ÛŒØ³ÛŒ',
      'pro': 'Ù¾Ø±Ùˆ',
      'pro_net_earning': 'Ù¾Ø±Ùˆ Ú©ÛŒ Ø®Ø§Ù„Øµ Ú©Ù…Ø§Ø¦ÛŒ',
      'professional': 'Ù¾Ø±ÙˆÙÛŒØ´Ù†Ù„',
      'profile': 'Ù¾Ø±ÙˆÙØ§Ø¦Ù„',
      'profile_photo': 'Ù¾Ø±ÙˆÙØ§Ø¦Ù„ ØªØµÙˆÛŒØ±',
      'profile_trust_message':
          'ØµØ§Ø±ÙÛŒÙ† Ú©Ø§ Ø§Ø¹ØªÙ…Ø§Ø¯ Ø¨Ù†Ø§Ù†Û’ Ú©Û’ Ù„ÛŒÛ’ Ø§Ù¾Ù†Ø§ Ù¾Ø±ÙˆÙØ§Ø¦Ù„ ÙˆØ§Ø¶Ø­ Ø§ÙˆØ± Ù¾ÛŒØ´Û ÙˆØ±Ø§Ù†Û Ø±Ú©Ú¾ÛŒÚºÛ”',
      'profile_updated': 'Ù¾Ø±ÙˆÙØ§Ø¦Ù„ Ø§Ù¾ÚˆÛŒÙ¹ ÛÙˆ Ú¯ÛŒØ§',
      'public_area_address': 'Ø¹Ù„Ø§Ù‚Û’ Ú©Ø§ Ø¹Ù…ÙˆÙ…ÛŒ Ù¾ØªÛ',
      'public_area_address_helper':
          'ÛŒÛ Ù‚Ø¨ÙˆÙ„ÛŒØª Ø³Û’ Ù¾ÛÙ„Û’ Ù†Ø¸Ø± Ø¢Ø¦Û’ Ú¯Ø§ (Ù…Ø«Ù„Ø§Ù‹ Ø³ÛŒÚ©Ù¹Ø± G-11ØŒ Ø§Ø³Ù„Ø§Ù… Ø¢Ø¨Ø§Ø¯)Û”',
      'push_notifications': 'Ù¾Ø´ Ù†ÙˆÙ¹ÛŒÙÚ©ÛŒØ´Ù†Ø²',
      'push_notifications_desc':
          'Ø¬Ø§Ø¨Ø²ØŒ Ø¨ÙˆÙ„ÛŒØŒ Ø§Ø³Ù¹ÛŒÙ¹Ø³ Ø§ÙˆØ± Ø§Ø¯Ø§Ø¦ÛŒÚ¯ÛŒ Ú©ÛŒ ÙÙˆØ±ÛŒ Ø§Ø·Ù„Ø§Ø¹Ø§Øª Ø­Ø§ØµÙ„ Ú©Ø±ÛŒÚº',
      'pros_around_you': 'professionals around you',
      'notification_permission_denied':
          'Ù†ÙˆÙ¹ÛŒÙÚ©ÛŒØ´Ù† Ú©ÛŒ Ø§Ø¬Ø§Ø²Øª Ù…Ø³ØªØ±Ø¯ ÛÙˆ Ú¯Ø¦ÛŒÛ” Ø¨Ø±Ø§Û Ú©Ø±Ù… ÚˆÛŒÙˆØ§Ø¦Ø³ Ø³ÛŒÙ¹Ù†Ú¯Ø² Ù…ÛŒÚº Ø§Ø¬Ø§Ø²Øª Ø¯ÛŒÚºÛ”',
      'raise_dispute': 'ØªÙ†Ø§Ø²Ø¹ Ø§Ù¹Ú¾Ø§Ø¦ÛŒÚº',
      'rating': 'Ø±ÛŒÙ¹Ù†Ú¯',
      'record_cash_payment': 'Ù†Ù‚Ø¯ Ø§Ø¯Ø§Ø¦ÛŒÚ¯ÛŒ Ø±ÛŒÚ©Ø§Ø±Úˆ Ú©Ø±ÛŒÚº',
      'register': 'Ø±Ø¬Ø³Ù¹Ø±',
      'register_subtitle_customer':
          'Ù‚Ø§Ø¨Ù„Ù Ø§Ø¹ØªÙ…Ø§Ø¯ Ù…Ù‚Ø§Ù…ÛŒ Ù…Ø§ÛØ±ÛŒÙ† Ú©ÛŒ Ø¨Ú©Ù†Ú¯ Ú©Û’ Ù„ÛŒÛ’ Ø§Ú©Ø§Ø¤Ù†Ù¹ Ø¨Ù†Ø§Ø¦ÛŒÚºÛ”',
      'register_subtitle_pro':
          'Ù¾Ø±ÙˆÙÛŒØ´Ù†Ù„ Ú©Û’ Ø·ÙˆØ± Ù¾Ø± Ø´Ø§Ù…Ù„ ÛÙˆÚº Ø§ÙˆØ± ÙÙˆØ±Ø§Ù‹ Ù‚Ø±ÛŒØ¨ÛŒ Ø¯Ø±Ø®ÙˆØ§Ø³ØªÛŒÚº Ø­Ø§ØµÙ„ Ú©Ø±ÛŒÚºÛ”',
      'registration_form': 'Ø±Ø¬Ø³Ù¹Ø±ÛŒØ´Ù† ÙØ§Ø±Ù…',
      'remove_photo': 'ØªØµÙˆÛŒØ± ÛÙ¹Ø§Ø¦ÛŒÚº',
      'required_field': 'Ø¶Ø±ÙˆØ±ÛŒ',
      'retry': 'Ø¯ÙˆØ¨Ø§Ø±Û Ú©ÙˆØ´Ø´ Ú©Ø±ÛŒÚº',
      'save': 'Ù…Ø­ÙÙˆØ¸ Ú©Ø±ÛŒÚº',
      'save_profile_changes':
          'Ù¾Ø±ÙˆÙØ§Ø¦Ù„ ØªØ¨Ø¯ÛŒÙ„ÛŒØ§Úº Ù…Ø­ÙÙˆØ¸ Ú©Ø±ÛŒÚº',
      'send_bid': 'Ø¨ÙˆÙ„ÛŒ Ø¨Ú¾ÛŒØ¬ÛŒÚº',
      'service_category': 'Ø³Ø±ÙˆØ³ Ú©ÛŒÙ¹ÛŒÚ¯Ø±ÛŒ',
      'settings': 'ØªØ±ØªÛŒØ¨Ø§Øª',
      'settings_subtitle':
          'Ø²Ø¨Ø§Ù†ØŒ Ù¾Ø±Ø§Ø¦ÛŒÙˆÛŒØ³ÛŒ Ø§ÙˆØ± Ù†ÙˆÙ¹ÛŒÙÚ©ÛŒØ´Ù† ØªØ±Ø¬ÛŒØ­Ø§Øª',
      'show_map': 'Ù†Ù‚Ø´Û Ø¯Ú©Ú¾Ø§Ø¦ÛŒÚº',
      'hide_map': 'Ù†Ù‚Ø´Û ÚچھÙ¾Ø§Ø¦ÛŒÚº',
      'sign_out_subtitle': 'Ø§Ø³ Ø§Ú©Ø§Ø¤Ù†Ù¹ Ø³Û’ Ø³Ø§Ø¦Ù† Ø¢Ø¤Ù¹ Ú©Ø±ÛŒÚº',
      'status': 'Ø§Ø³Ù¹ÛŒÙ¹Ø³',
      'status_available': 'Ø¯Ø³ØªÛŒØ§Ø¨',
      'status_cancelled': 'Ù…Ù†Ø³ÙˆØ®',
      'status_completed': 'Ù…Ú©Ù…Ù„',
      'status_disputed': 'Ù…ØªÙ†Ø§Ø²Ø¹',
      'status_in_process': 'Ø¹Ù…Ù„ Ø¬Ø§Ø±ÛŒ',
      'status_paid_closed': 'Ø§Ø¯Ø§ Ø´Ø¯Û Ø§ÙˆØ± Ø¨Ù†Ø¯',
      'status_posted': 'Ù¾ÙˆØ³Ù¹ Ú©ÛŒ Ú¯Ø¦ÛŒ',
      'take_picture': 'ØªØµÙˆÛŒØ± Ù„ÛŒÚº',
      'tap_profile_photo_hint':
          'Ú¯ÛŒÙ„Ø±ÛŒ ÛŒØ§ Ú©ÛŒÙ…Ø±Û Ú©Û’ Ù„ÛŒÛ’ Ø§ÙˆÙ¾Ø± Ù¾Ø±ÙˆÙØ§Ø¦Ù„ ØªØµÙˆÛŒØ± Ù¾Ø± Ù¹ÛŒÙ¾ Ú©Ø±ÛŒÚºÛ”',
      'terms': 'Ø´Ø±Ø§Ø¦Ø·',
      'terms_acceptance_records': 'Ø´Ø±Ø§Ø¦Ø· Ù‚Ø¨ÙˆÙ„ÛŒØª Ú©Û’ Ø±ÛŒÚ©Ø§Ø±Úˆ',
      'terms_conditions': 'Ø´Ø±Ø§Ø¦Ø· Ùˆ Ø¶ÙˆØ§Ø¨Ø·',
      'terms_content':
          'Ø§Ú©Ø§Ø¤Ù†Ù¹ Ø¨Ù†Ø§Ù†Û’ Ø³Û’ Ø¢Ù¾ Ø¯Ø±Ø³Øª Ù…Ø¹Ù„ÙˆÙ…Ø§Øª ÙØ±Ø§ÛÙ… Ú©Ø±Ù†Û’ØŒ Ù‚Ø§Ù†ÙˆÙ†ÛŒ Ø®Ø¯Ù…Ø§Øª Ø§Ø³ØªØ¹Ù…Ø§Ù„ Ú©Ø±Ù†Û’ Ø§ÙˆØ± Ù…Ø§Ø±Ú©ÛŒÙ¹ Ù¾Ù„ÛŒØ³ Ù‚ÙˆØ§Ø¹Ø¯ Ú©ÛŒ Ù¾Ø§Ø¨Ù†Ø¯ÛŒ Ù¾Ø± Ù…ØªÙÙ‚ ÛÙˆØªÛ’ ÛÛŒÚºÛ” Ø¬Ø§Ø¨ Ø§Ø³Ù¹ÛŒÙ¹Ø³ØŒ ØªÙ†Ø§Ø²Ø¹Ø§ØªØŒ Ù…Ù†Ø³ÙˆØ®ÛŒØ§ÚºØŒ Ø§Ø¯Ø§Ø¦ÛŒÚ¯ÛŒØ§Úº Ø§ÙˆØ± ØªØµØ¯ÛŒÙ‚ÛŒ ÙˆØ§Ù‚Ø¹Ø§Øª Ø§Ø¹ØªÙ…Ø§Ø¯ Ø§ÙˆØ± Ù‚Ø§Ù†ÙˆÙ†ÛŒ ØªØ¹Ù…ÛŒÙ„ Ú©Û’ Ù„ÛŒÛ’ Ø¢ÚˆÙ¹ Ø§ÛŒØ¨Ù„ Ø·ÙˆØ± Ù¾Ø± Ø±ÛŒÚ©Ø§Ø±Úˆ Ú©ÛŒÛ’ Ø¬Ø§ØªÛ’ ÛÛŒÚºÛ”',
      'terms_privacy_required':
          'Ø¨Ø±Ø§Û Ú©Ø±Ù… Ø´Ø±Ø§Ø¦Ø· Ùˆ Ø¶ÙˆØ§Ø¨Ø· Ù‚Ø¨ÙˆÙ„ Ú©Ø±ÛŒÚºÛ”',
      'terms_records': 'Ø´Ø±Ø§Ø¦Ø· Ú©Û’ Ø±ÛŒÚ©Ø§Ø±Úˆ',
      'this_month': 'Ø§Ø³ Ù…Ø§Û',
      'timeline_audit_trail': 'Ù¹Ø§Ø¦Ù… Ù„Ø§Ø¦Ù† Ø§ÙˆØ± Ø¢ÚˆÙ¹ Ù¹Ø±ÛŒÙ„',
      'timeline_subtitle':
          'ÛØ± Ø§Ø³Ù¹ÛŒÙ¹/Ø¹Ù…Ù„ ÙˆÙ‚Øª Ú©Û’ Ø³Ø§ØªÚ¾ Ù…Ø³ØªÙ‚Ù„ Ø·ÙˆØ± Ù¾Ø± Ø±ÛŒÚ©Ø§Ø±Úˆ ÛÙˆØªØ§ ÛÛ’',
      'today': 'Ø¢Ø¬',
      'type_message': 'Ø§Ù¾Ù†Ø§ Ù¾ÛŒØºØ§Ù… Ù„Ú©Ú¾ÛŒÚº',
      'update': 'Ø§Ù¾ÚˆÛŒÙ¹',
      'upload_from_gallery': 'Ú¯ÛŒÙ„Ø±ÛŒ Ø³Û’ Ø§Ù¾Ù„ÙˆÚˆ Ú©Ø±ÛŒÚº',
      'urdu': 'Ø§Ø±Ø¯Ùˆ',
      'user_raised_dispute': 'ØµØ§Ø±Ù Ù†Û’ ØªÙ†Ø§Ø²Ø¹ Ø§Ù¹Ú¾Ø§ÛŒØ§',
      'user_requested_cancellation':
          'ØµØ§Ø±Ù Ù†Û’ Ù…Ù†Ø³ÙˆØ®ÛŒ Ú©ÛŒ Ø¯Ø±Ø®ÙˆØ§Ø³Øª Ú©ÛŒ',
      'verification': 'ØªØµØ¯ÛŒÙ‚',
      'verified': 'ØªØµØ¯ÛŒÙ‚ Ø´Ø¯Û',
      'your_pending_jobs': 'Ø¢Ù¾ Ú©ÛŒ Ø²ÛŒØ±Ù Ø§Ù„ØªÙˆØ§ Ø¬Ø§Ø¨Ø²',
      'requests_loading': 'Ø¯Ø±Ø®ÙˆØ§Ø³ØªÛŒÚº Ù„ÙˆÚڈ ØÙˆ Ø±ÛŒ ÛÛŒÚº',
      'your_bid_amount': 'Ø¢Ù¾ Ú©ÛŒ Ø¨ÙˆÙ„ÛŒ Ú©ÛŒ Ø±Ù‚Ù…',
      'your_location': 'Ø¢Ù¾ Ú©ÛŒ Ù„ÙˆÚ©ÛŒØ´Ù†',
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
