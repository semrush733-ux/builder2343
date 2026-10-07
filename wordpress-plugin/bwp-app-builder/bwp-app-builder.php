<?php
/**
 * Plugin Name:       BWP App Builder
 * Description:       Turn any website into an iPhone app (IPA) and an Android app (APK) with one click. Add the form with the shortcode [bwp_app_builder]. Builds run on GitHub Actions.
 * Version:           1.0.0
 * Author:            BWP Experts
 * Requires at least: 5.8
 * Requires PHP:      7.4
 * License:           GPL-2.0-or-later
 * Text Domain:       bwp-app-builder
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

final class BWP_App_Builder {

	const VERSION   = '1.0.0';
	const OPTION    = 'bwp_app_builder_settings';
	const POST_TYPE = 'bwp_app_build';
	const NONCE     = 'bwpab';
	const CRON      = 'bwp_app_builder_cleanup';
	const API       = 'https://api.github.com';
	const API_VERSION = '2026-03-10';

	/** Minutes after which a build without a result is treated as failed. */
	const TIMEOUT_MINUTES = 60;

	/** Days after which finished builds and their uploaded logos are removed. */
	const KEEP_DAYS = 7;

	private static $instance = null;

	public static function instance() {
		if ( null === self::$instance ) {
			self::$instance = new self();
		}
		return self::$instance;
	}

	private function __construct() {
		add_action( 'init', array( $this, 'register_post_type' ) );
		add_action( 'admin_menu', array( $this, 'admin_menu' ) );
		add_action( 'admin_init', array( $this, 'register_settings' ) );
		add_action( 'admin_post_bwpab_test', array( $this, 'handle_connection_test' ) );
		add_shortcode( 'bwp_app_builder', array( $this, 'shortcode' ) );

		add_action( 'wp_ajax_bwpab_start', array( $this, 'ajax_start' ) );
		add_action( 'wp_ajax_nopriv_bwpab_start', array( $this, 'ajax_start' ) );
		add_action( 'wp_ajax_bwpab_status', array( $this, 'ajax_status' ) );
		add_action( 'wp_ajax_nopriv_bwpab_status', array( $this, 'ajax_status' ) );
		add_action( 'admin_post_bwpab_download', array( $this, 'handle_download' ) );
		add_action( 'admin_post_nopriv_bwpab_download', array( $this, 'handle_download' ) );

		add_action( self::CRON, array( $this, 'cleanup' ) );
	}

	public static function activate() {
		if ( ! wp_next_scheduled( self::CRON ) ) {
			wp_schedule_event( time() + HOUR_IN_SECONDS, 'daily', self::CRON );
		}
	}

	public static function deactivate() {
		wp_clear_scheduled_hook( self::CRON );
	}

	/* ------------------------------------------------------------------ settings */

	public static function defaults() {
		return array(
			'owner'       => '',
			'repo'        => '',
			'workflow'    => 'build-app.yml',
			'branch'      => 'main',
			'token'       => '',
			'access'      => 'logged_in', // admin | logged_in | public.
			'platforms'   => 'both',      // ios | android | both.
			'daily_limit' => 3,
			'max_active'  => 2,
		);
	}

	public function settings() {
		$saved    = get_option( self::OPTION, array() );
		$settings = wp_parse_args( is_array( $saved ) ? $saved : array(), self::defaults() );
		// The token can also be kept out of the database:  define( 'BWP_APP_BUILDER_GITHUB_TOKEN', '...' );  in wp-config.php.
		if ( defined( 'BWP_APP_BUILDER_GITHUB_TOKEN' ) && BWP_APP_BUILDER_GITHUB_TOKEN ) {
			$settings['token'] = (string) BWP_APP_BUILDER_GITHUB_TOKEN;
		}
		return $settings;
	}

	public function is_configured() {
		$s = $this->settings();
		return '' !== $s['owner'] && '' !== $s['repo'] && '' !== $s['token'] && '' !== $s['workflow'];
	}

	public function register_settings() {
		register_setting(
			'bwp_app_builder',
			self::OPTION,
			array(
				'type'              => 'array',
				'sanitize_callback' => array( $this, 'sanitize_settings' ),
				'default'           => self::defaults(),
			)
		);
	}

	public function sanitize_settings( $input ) {
		$old   = wp_parse_args( (array) get_option( self::OPTION, array() ), self::defaults() );
		$input = is_array( $input ) ? $input : array();
		$clean = array();

		$clean['owner']    = preg_replace( '/[^A-Za-z0-9_.-]/', '', isset( $input['owner'] ) ? (string) $input['owner'] : '' );
		$clean['repo']     = preg_replace( '/[^A-Za-z0-9_.-]/', '', isset( $input['repo'] ) ? (string) $input['repo'] : '' );
		$clean['workflow'] = preg_replace( '/[^A-Za-z0-9_.-]/', '', isset( $input['workflow'] ) ? (string) $input['workflow'] : '' );
		$clean['branch']   = preg_replace( '/[^A-Za-z0-9_.\/-]/', '', isset( $input['branch'] ) ? (string) $input['branch'] : '' );
		if ( '' === $clean['workflow'] ) {
			$clean['workflow'] = 'build-app.yml';
		}
		if ( '' === $clean['branch'] ) {
			$clean['branch'] = 'main';
		}

		// An empty token field keeps the stored token, so it never has to be shown again.
		$token          = isset( $input['token'] ) ? trim( (string) $input['token'] ) : '';
		$clean['token'] = '' !== $token ? preg_replace( '/[^A-Za-z0-9_]/', '', $token ) : $old['token'];
		if ( ! empty( $input['remove_token'] ) ) {
			$clean['token'] = '';
		}

		$access             = isset( $input['access'] ) ? (string) $input['access'] : '';
		$clean['access']    = in_array( $access, array( 'admin', 'logged_in', 'public' ), true ) ? $access : 'logged_in';
		$platforms          = isset( $input['platforms'] ) ? (string) $input['platforms'] : '';
		$clean['platforms'] = in_array( $platforms, array( 'ios', 'android', 'both' ), true ) ? $platforms : 'both';

		$clean['daily_limit'] = max( 1, min( 500, absint( isset( $input['daily_limit'] ) ? $input['daily_limit'] : 3 ) ) );
		$clean['max_active']  = max( 1, min( 20, absint( isset( $input['max_active'] ) ? $input['max_active'] : 2 ) ) );

		return $clean;
	}

	/* ------------------------------------------------------------------ access */

	public function can_use() {
		$s = $this->settings();
		if ( current_user_can( 'manage_options' ) ) {
			return true;
		}
		if ( 'public' === $s['access'] ) {
			return true;
		}
		if ( 'logged_in' === $s['access'] ) {
			return is_user_logged_in();
		}
		return false;
	}

	private function visitor_key() {
		$ip = isset( $_SERVER['REMOTE_ADDR'] ) ? sanitize_text_field( wp_unslash( $_SERVER['REMOTE_ADDR'] ) ) : '';
		return hash_hmac( 'sha256', $ip, wp_salt( 'auth' ) );
	}

	/* ------------------------------------------------------------------ data */

	public function register_post_type() {
		register_post_type(
			self::POST_TYPE,
			array(
				'label'               => 'App builds',
				'public'              => false,
				'show_ui'             => false,
				'exclude_from_search' => true,
				'publicly_queryable'  => false,
				'rewrite'             => false,
				'supports'            => array( 'title', 'author' ),
				'can_export'          => false,
			)
		);
	}

	private function find_build( $build_id ) {
		if ( ! is_string( $build_id ) || ! preg_match( '/^[a-z0-9]{8,40}$/', $build_id ) ) {
			return null;
		}
		$posts = get_posts(
			array(
				'post_type'        => self::POST_TYPE,
				'post_status'      => 'private',
				'posts_per_page'   => 1,
				'meta_key'         => '_bwpab_id', // phpcs:ignore WordPress.DB.SlowDBQuery
				'meta_value'       => $build_id,   // phpcs:ignore WordPress.DB.SlowDBQuery
				'suppress_filters' => true,
				'no_found_rows'    => true,
			)
		);
		return $posts ? $posts[0] : null;
	}

	private function recent_builds( $args = array() ) {
		return get_posts(
			wp_parse_args(
				$args,
				array(
					'post_type'        => self::POST_TYPE,
					'post_status'      => 'private',
					'posts_per_page'   => 200,
					'suppress_filters' => true,
					'no_found_rows'    => true,
					'date_query'       => array( array( 'after' => '24 hours ago' ) ),
				)
			)
		);
	}

	private function count_active() {
		$count = 0;
		foreach ( $this->recent_builds( array( 'date_query' => array( array( 'after' => self::TIMEOUT_MINUTES . ' minutes ago' ) ) ) ) as $post ) {
			if ( in_array( get_post_meta( $post->ID, '_bwpab_status', true ), array( 'queued', 'building' ), true ) ) {
				$count++;
			}
		}
		return $count;
	}

	private function count_today_for_visitor() {
		$user  = get_current_user_id();
		$key   = $this->visitor_key();
		$count = 0;
		foreach ( $this->recent_builds() as $post ) {
			$same_user = $user && (int) $post->post_author === $user;
			$same_ip   = ! $user && get_post_meta( $post->ID, '_bwpab_visitor', true ) === $key;
			if ( $same_user || $same_ip ) {
				$count++;
			}
		}
		return $count;
	}

	/* ------------------------------------------------------------------ GitHub */

	/**
	 * @return array{code:int,body:mixed,raw:string,headers:mixed}|WP_Error
	 */
	private function github( $method, $path, $body = null, $extra = array() ) {
		$s    = $this->settings();
		$args = array(
			'method'      => $method,
			'timeout'     => 25,
			'redirection' => 3,
			'headers'     => array(
				'Authorization'        => 'Bearer ' . $s['token'],
				'Accept'               => 'application/vnd.github+json',
				'X-GitHub-Api-Version' => self::API_VERSION,
				'User-Agent'           => 'bwp-app-builder/' . self::VERSION,
			),
		);
		if ( null !== $body ) {
			$args['body']                    = wp_json_encode( $body );
			$args['headers']['Content-Type'] = 'application/json';
		}
		$args     = array_replace_recursive( $args, $extra );
		$response = wp_remote_request( self::API . $path, $args );
		if ( is_wp_error( $response ) ) {
			return $response;
		}
		$raw = (string) wp_remote_retrieve_body( $response );
		return array(
			'code'    => (int) wp_remote_retrieve_response_code( $response ),
			'body'    => '' !== $raw ? json_decode( $raw, true ) : null,
			'raw'     => $raw,
			'headers' => wp_remote_retrieve_headers( $response ),
		);
	}

	private function repo_path() {
		$s = $this->settings();
		return '/repos/' . rawurlencode( $s['owner'] ) . '/' . rawurlencode( $s['repo'] );
	}

	private function github_message( $result ) {
		if ( is_wp_error( $result ) ) {
			return $result->get_error_message();
		}
		$message = is_array( $result['body'] ) && isset( $result['body']['message'] ) ? (string) $result['body']['message'] : '';
		return trim( 'HTTP ' . $result['code'] . ' ' . $message );
	}

	/* ------------------------------------------------------------------ request validation */

	/**
	 * Builds the request sent to the workflow. The workflow validates everything again.
	 *
	 * @return array|WP_Error
	 */
	private function read_request() {
		// phpcs:disable WordPress.Security.NonceVerification.Missing -- verified in ajax_start().
		$name = isset( $_POST['app_name'] ) ? sanitize_text_field( wp_unslash( $_POST['app_name'] ) ) : '';
		$name = trim( preg_replace( '/\s+/', ' ', str_replace( array( '<', '>', '&', '"', "'", '`', '\\', '/', '{', '}', '$', '%' ), '', $name ) ) );
		$len  = function_exists( 'mb_strlen' ) ? mb_strlen( $name ) : strlen( $name );
		if ( $len < 2 || $len > 30 ) {
			return new WP_Error( 'name', __( 'Enter an app name of 2 to 30 characters.', 'bwp-app-builder' ) );
		}

		$url = isset( $_POST['site_url'] ) ? trim( sanitize_text_field( wp_unslash( $_POST['site_url'] ) ) ) : '';
		if ( '' !== $url && ! preg_match( '#^[a-z][a-z0-9+.-]*://#i', $url ) ) {
			$url = 'https://' . $url;
		}
		$url   = esc_url_raw( $url, array( 'https' ) );
		$parts = $url ? wp_parse_url( $url ) : false;
		$host  = is_array( $parts ) && ! empty( $parts['host'] ) ? strtolower( $parts['host'] ) : '';
		if ( ! $url || ! is_array( $parts ) || empty( $parts['scheme'] ) || 'https' !== strtolower( $parts['scheme'] ) ) {
			return new WP_Error( 'url', __( 'Enter the website address starting with https://', 'bwp-app-builder' ) );
		}
		if ( ! preg_match( '/^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}$/', $host ) || ! empty( $parts['user'] ) || ! empty( $parts['pass'] ) ) {
			return new WP_Error( 'url', __( 'Enter a public website address, for example https://example.com', 'bwp-app-builder' ) );
		}

		$config = array(
			'appName' => $name,
			'homeUrl' => $url,
		);

		$app_id = isset( $_POST['app_id'] ) ? strtolower( trim( sanitize_text_field( wp_unslash( $_POST['app_id'] ) ) ) ) : '';
		if ( '' !== $app_id ) {
			if ( ! preg_match( '/^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*){1,5}$/', $app_id ) ) {
				return new WP_Error( 'app_id', __( 'App ID must look like com.company.app (lowercase letters, digits and dots).', 'bwp-app-builder' ) );
			}
			$config['appId'] = $app_id;
		}

		$company = isset( $_POST['company'] ) ? sanitize_text_field( wp_unslash( $_POST['company'] ) ) : '';
		$company = trim( str_replace( array( '<', '>', '&', '"', "'", '`', '\\', '{', '}', '$', '%' ), '', $company ) );
		if ( '' !== $company ) {
			$config['company'] = function_exists( 'mb_substr' ) ? mb_substr( $company, 0, 40 ) : substr( $company, 0, 40 );
		}

		foreach ( array( 'brand_color' => 'brandColor', 'background_color' => 'backgroundColor' ) as $field => $key ) {
			$color = isset( $_POST[ $field ] ) ? sanitize_hex_color( wp_unslash( $_POST[ $field ] ) ) : '';
			if ( $color && 7 === strlen( $color ) ) {
				$config[ $key ] = strtoupper( $color );
			}
		}

		$offered   = $this->settings()['platforms'];
		$platforms = isset( $_POST['platforms'] ) ? sanitize_key( wp_unslash( $_POST['platforms'] ) ) : $offered;
		if ( ! in_array( $platforms, array( 'ios', 'android', 'both' ), true ) ) {
			$platforms = $offered;
		}
		if ( 'both' !== $offered ) {
			$platforms = $offered;
		}
		// phpcs:enable

		return array(
			'config'    => $config,
			'platforms' => $platforms,
			'host'      => $host,
		);
	}

	/**
	 * Stores the uploaded logo in uploads/bwp-app-builder/ and returns its public URL.
	 *
	 * @return array{url:string,path:string}|WP_Error|null  null when no logo was sent.
	 */
	private function store_logo() {
		// phpcs:disable WordPress.Security.NonceVerification.Missing -- verified in ajax_start().
		if ( empty( $_FILES['logo'] ) || ! is_array( $_FILES['logo'] ) || empty( $_FILES['logo']['name'] ) ) {
			return null;
		}
		$file = $_FILES['logo']; // phpcs:ignore WordPress.Security.ValidatedSanitizedInput -- checked below and by wp_handle_upload().
		// phpcs:enable
		if ( ! empty( $file['error'] ) ) {
			return new WP_Error( 'logo', __( 'The logo could not be uploaded. Try a smaller PNG or JPG file.', 'bwp-app-builder' ) );
		}
		if ( (int) $file['size'] > 5 * MB_IN_BYTES ) {
			return new WP_Error( 'logo', __( 'The logo must be smaller than 5 MB.', 'bwp-app-builder' ) );
		}
		$mimes = array(
			'png'          => 'image/png',
			'jpg|jpeg|jpe' => 'image/jpeg',
			'webp'         => 'image/webp',
		);
		$check = wp_check_filetype_and_ext( $file['tmp_name'], $file['name'], $mimes );
		if ( empty( $check['ext'] ) || empty( $check['type'] ) || false === @getimagesize( $file['tmp_name'] ) ) { // phpcs:ignore WordPress.PHP.NoSilencedErrors
			return new WP_Error( 'logo', __( 'The logo must be a PNG, JPG or WebP image.', 'bwp-app-builder' ) );
		}

		require_once ABSPATH . 'wp-admin/includes/file.php';
		$file['name'] = 'logo-' . strtolower( wp_generate_password( 20, false ) ) . '.' . $check['ext'];

		$filter = array( $this, 'upload_dir' );
		add_filter( 'upload_dir', $filter );
		$moved = wp_handle_upload(
			$file,
			array(
				'test_form' => false,
				'mimes'     => $mimes,
			)
		);
		remove_filter( 'upload_dir', $filter );

		if ( ! is_array( $moved ) || ! empty( $moved['error'] ) || empty( $moved['url'] ) ) {
			return new WP_Error( 'logo', __( 'The logo could not be saved. Please try again.', 'bwp-app-builder' ) );
		}
		return array(
			'url'  => set_url_scheme( $moved['url'], 'https' ),
			'path' => $moved['file'],
		);
	}

	public function upload_dir( $dirs ) {
		$dirs['subdir'] = '/bwp-app-builder';
		$dirs['path']   = $dirs['basedir'] . '/bwp-app-builder';
		$dirs['url']    = $dirs['baseurl'] . '/bwp-app-builder';
		return $dirs;
	}

	/* ------------------------------------------------------------------ start a build */

	public function ajax_start() {
		if ( ! check_ajax_referer( self::NONCE, 'nonce', false ) ) {
			wp_send_json_error( array( 'message' => __( 'This page has expired. Reload it and try again.', 'bwp-app-builder' ) ), 403 );
		}
		if ( ! $this->can_use() ) {
			wp_send_json_error( array( 'message' => __( 'You are not allowed to build apps here.', 'bwp-app-builder' ) ), 403 );
		}
		$admin = current_user_can( 'manage_options' );
		if ( ! $this->is_configured() ) {
			wp_send_json_error(
				array(
					'message' => $admin
						? __( 'The app builder is not set up yet. Open Settings > App Builder and add the GitHub details.', 'bwp-app-builder' )
						: __( 'The app builder is not available right now.', 'bwp-app-builder' ),
				),
				503
			);
		}

		$request = $this->read_request();
		if ( is_wp_error( $request ) ) {
			wp_send_json_error( array( 'message' => $request->get_error_message() ), 400 );
		}

		$s = $this->settings();
		if ( ! $admin && $this->count_today_for_visitor() >= (int) $s['daily_limit'] ) {
			wp_send_json_error( array( 'message' => __( 'You have reached the limit of app builds for today. Please try again tomorrow.', 'bwp-app-builder' ) ), 429 );
		}
		if ( $this->count_active() >= (int) $s['max_active'] ) {
			wp_send_json_error( array( 'message' => __( 'Other apps are being built right now. Please try again in a few minutes.', 'bwp-app-builder' ) ), 429 );
		}

		$logo = $this->store_logo();
		if ( is_wp_error( $logo ) ) {
			wp_send_json_error( array( 'message' => $logo->get_error_message() ), 400 );
		}

		$build_id = strtolower( wp_generate_password( 24, false ) );
		$post_id  = wp_insert_post(
			array(
				'post_type'   => self::POST_TYPE,
				'post_status' => 'private',
				'post_title'  => $request['config']['appName'],
				'post_author' => get_current_user_id(),
			),
			true
		);
		if ( is_wp_error( $post_id ) || ! $post_id ) {
			wp_send_json_error( array( 'message' => __( 'The build could not be saved. Please try again.', 'bwp-app-builder' ) ), 500 );
		}
		update_post_meta( $post_id, '_bwpab_id', $build_id );
		update_post_meta( $post_id, '_bwpab_status', 'queued' );
		update_post_meta( $post_id, '_bwpab_platforms', $request['platforms'] );
		update_post_meta( $post_id, '_bwpab_url', $request['config']['homeUrl'] );
		update_post_meta( $post_id, '_bwpab_visitor', $this->visitor_key() );
		update_post_meta( $post_id, '_bwpab_started', time() );
		if ( is_array( $logo ) ) {
			update_post_meta( $post_id, '_bwpab_logo', $logo['path'] );
		}

		$result = $this->github(
			'POST',
			$this->repo_path() . '/actions/workflows/' . rawurlencode( $s['workflow'] ) . '/dispatches',
			array(
				'ref'    => $s['branch'],
				'inputs' => array(
					'build_id'  => $build_id,
					'config'    => wp_json_encode( $request['config'] ),
					'logo_url'  => is_array( $logo ) ? $logo['url'] : '',
					'platforms' => $request['platforms'],
				),
			)
		);

		if ( is_wp_error( $result ) || $result['code'] < 200 || $result['code'] >= 300 ) {
			$detail = $this->github_message( $result );
			update_post_meta( $post_id, '_bwpab_status', 'failed' );
			update_post_meta( $post_id, '_bwpab_error', 'Could not start the build: ' . $detail );
			wp_send_json_error(
				array(
					'message' => $admin
						/* translators: %s: error returned by GitHub */
						? sprintf( __( 'GitHub did not accept the build: %s', 'bwp-app-builder' ), $detail )
						: __( 'The build could not be started. Please try again later.', 'bwp-app-builder' ),
				),
				502
			);
		}

		wp_send_json_success( $this->public_state( get_post( $post_id ) ) );
	}

	/* ------------------------------------------------------------------ status */

	public function ajax_status() {
		// The build ID is a 24-character random secret; knowing it is the permission to see the build.
		// phpcs:ignore WordPress.Security.NonceVerification.Recommended
		$build_id = isset( $_REQUEST['id'] ) ? sanitize_key( wp_unslash( $_REQUEST['id'] ) ) : '';
		$post     = $this->find_build( $build_id );
		if ( ! $post ) {
			wp_send_json_error( array( 'message' => __( 'This build was not found. It may have been removed.', 'bwp-app-builder' ) ), 404 );
		}
		$this->refresh( $post );
		wp_send_json_success( $this->public_state( $post ) );
	}

	/** Asks GitHub for the state of a build and stores it. Finished builds are never asked again. */
	private function refresh( $post ) {
		$status = get_post_meta( $post->ID, '_bwpab_status', true );
		if ( in_array( $status, array( 'done', 'failed' ), true ) ) {
			return;
		}
		$build_id = get_post_meta( $post->ID, '_bwpab_id', true );
		$throttle = 'bwpab_poll_' . $build_id;
		if ( get_transient( $throttle ) ) {
			return;
		}
		set_transient( $throttle, 1, 6 );

		$age    = time() - (int) get_post_meta( $post->ID, '_bwpab_started', true );
		$result = $this->github( 'GET', $this->repo_path() . '/releases/tags/build-' . $build_id );

		if ( is_wp_error( $result ) ) {
			return; // Temporary network problem: keep the current state and try again on the next poll.
		}

		if ( 404 === $result['code'] ) {
			// The workflow has not opened its release yet.
			if ( $age > 20 * MINUTE_IN_SECONDS ) {
				$this->fail( $post, 'The build did not start within 20 minutes.' );
			}
			return;
		}
		if ( 200 !== $result['code'] || ! is_array( $result['body'] ) ) {
			update_post_meta( $post->ID, '_bwpab_error', 'GitHub: ' . $this->github_message( $result ) );
			if ( $age > self::TIMEOUT_MINUTES * MINUTE_IN_SECONDS ) {
				$this->fail( $post, 'GitHub could not be reached: ' . $this->github_message( $result ) );
			}
			return;
		}

		$release = $result['body'];
		$notes   = isset( $release['body'] ) ? json_decode( (string) $release['body'], true ) : null;
		$notes   = is_array( $notes ) ? $notes : array();
		$state   = isset( $notes['status'] ) ? (string) $notes['status'] : 'building';

		if ( 'done' !== $state ) {
			update_post_meta( $post->ID, '_bwpab_status', 'building' );
			if ( $age > self::TIMEOUT_MINUTES * MINUTE_IN_SECONDS ) {
				$this->fail( $post, 'The build took too long and was given up.' );
			}
			return;
		}

		$files = array();
		foreach ( isset( $release['assets'] ) && is_array( $release['assets'] ) ? $release['assets'] : array() as $asset ) {
			$name = isset( $asset['name'] ) ? (string) $asset['name'] : '';
			$ext  = strtolower( pathinfo( $name, PATHINFO_EXTENSION ) );
			$kind = 'ipa' === $ext ? 'ios' : ( 'apk' === $ext ? 'android' : '' );
			if ( $kind && ! empty( $asset['id'] ) ) {
				$files[ $kind ] = array(
					'id'   => (int) $asset['id'],
					'name' => sanitize_file_name( $name ),
					'size' => isset( $asset['size'] ) ? (int) $asset['size'] : 0,
					'link' => isset( $asset['browser_download_url'] ) ? esc_url_raw( (string) $asset['browser_download_url'], array( 'https' ) ) : '',
				);
			}
		}

		$clean = function ( $list ) {
			$out = array();
			foreach ( is_array( $list ) ? $list : array() as $line ) {
				$out[] = sanitize_text_field( (string) $line );
			}
			return array_slice( $out, 0, 10 );
		};

		update_post_meta( $post->ID, '_bwpab_files', $files );
		update_post_meta( $post->ID, '_bwpab_warnings', $clean( isset( $notes['warnings'] ) ? $notes['warnings'] : array() ) );
		update_post_meta( $post->ID, '_bwpab_errors', $clean( isset( $notes['errors'] ) ? $notes['errors'] : array() ) );
		update_post_meta( $post->ID, '_bwpab_run', isset( $notes['run_id'] ) ? preg_replace( '/\D/', '', (string) $notes['run_id'] ) : '' );
		update_post_meta( $post->ID, '_bwpab_finished', time() );

		if ( $files ) {
			update_post_meta( $post->ID, '_bwpab_status', 'done' );
		} else {
			$this->fail( $post, 'The build finished without producing an app.' );
		}
	}

	private function fail( $post, $reason ) {
		update_post_meta( $post->ID, '_bwpab_status', 'failed' );
		update_post_meta( $post->ID, '_bwpab_error', $reason );
		update_post_meta( $post->ID, '_bwpab_finished', time() );
	}

	/** What the browser is allowed to know about a build. */
	private function public_state( $post ) {
		$build_id  = get_post_meta( $post->ID, '_bwpab_id', true );
		$status    = get_post_meta( $post->ID, '_bwpab_status', true );
		$platforms = get_post_meta( $post->ID, '_bwpab_platforms', true );
		$files     = get_post_meta( $post->ID, '_bwpab_files', true );
		$files     = is_array( $files ) ? $files : array();
		$admin     = current_user_can( 'manage_options' );

		$downloads = array();
		foreach ( array( 'ios', 'android' ) as $kind ) {
			$wanted = 'both' === $platforms || $kind === $platforms;
			if ( ! $wanted ) {
				continue;
			}
			if ( isset( $files[ $kind ] ) ) {
				$downloads[ $kind ] = array(
					'ok'   => true,
					'name' => $files[ $kind ]['name'],
					'size' => size_format( $files[ $kind ]['size'], 1 ),
					'url'  => add_query_arg(
						array(
							'action' => 'bwpab_download',
							'id'     => $build_id,
							'file'   => $kind,
						),
						admin_url( 'admin-post.php' )
					),
				);
			} elseif ( 'done' === $status ) {
				$downloads[ $kind ] = array( 'ok' => false );
			}
		}

		$state = array(
			'id'        => $build_id,
			'status'    => $status ? $status : 'queued',
			'appName'   => $post->post_title,
			'platforms' => $platforms,
			'elapsed'   => max( 0, time() - (int) get_post_meta( $post->ID, '_bwpab_started', true ) ),
			'downloads' => $downloads,
			'warnings'  => array_values( (array) get_post_meta( $post->ID, '_bwpab_warnings', true ) ),
			'message'   => '',
		);
		if ( 'failed' === $status ) {
			$state['message'] = __( 'The app could not be built. Please check the website address and try again.', 'bwp-app-builder' );
			if ( $admin ) {
				$errors            = array_filter( array_merge( array( (string) get_post_meta( $post->ID, '_bwpab_error', true ) ), (array) get_post_meta( $post->ID, '_bwpab_errors', true ) ) );
				$state['message'] .= ' ' . implode( ' | ', array_map( 'sanitize_text_field', $errors ) );
			}
		}
		return $state;
	}

	/* ------------------------------------------------------------------ download */

	/** Streams a finished app from GitHub to the browser, so the GitHub token and repository stay private. */
	public function handle_download() {
		// phpcs:disable WordPress.Security.NonceVerification.Recommended -- the random build ID is the permission.
		$build_id = isset( $_GET['id'] ) ? sanitize_key( wp_unslash( $_GET['id'] ) ) : '';
		$kind     = isset( $_GET['file'] ) ? sanitize_key( wp_unslash( $_GET['file'] ) ) : '';
		// phpcs:enable
		$post  = $this->find_build( $build_id );
		$files = $post ? get_post_meta( $post->ID, '_bwpab_files', true ) : array();
		if ( ! $post || ! is_array( $files ) || empty( $files[ $kind ]['id'] ) ) {
			wp_die( esc_html__( 'This file is no longer available. Please build the app again.', 'bwp-app-builder' ), '', array( 'response' => 404 ) );
		}
		$file = $files[ $kind ];

		require_once ABSPATH . 'wp-admin/includes/file.php';
		$tmp = wp_tempnam( 'bwpab' );
		if ( ! $tmp ) {
			wp_die( esc_html__( 'The download could not be prepared. Please try again.', 'bwp-app-builder' ), '', array( 'response' => 500 ) );
		}

		// Step 1: ask the API for the file. GitHub answers with a redirect to a short-lived storage URL.
		$first = $this->github(
			'GET',
			$this->repo_path() . '/releases/assets/' . (int) $file['id'],
			null,
			array(
				'timeout'     => 120,
				'redirection' => 0,
				'stream'      => true,
				'filename'    => $tmp,
				'headers'     => array( 'Accept' => 'application/octet-stream' ),
			)
		);
		$ok = ! is_wp_error( $first ) && 200 === $first['code'];

		// Step 2: follow the redirect WITHOUT the token (the storage host rejects extra credentials).
		if ( ! $ok && ! is_wp_error( $first ) && in_array( $first['code'], array( 301, 302, 303, 307, 308 ), true ) ) {
			$location = '';
			if ( is_object( $first['headers'] ) && isset( $first['headers']['location'] ) ) {
				$location = $first['headers']['location'];
			} elseif ( is_array( $first['headers'] ) && isset( $first['headers']['location'] ) ) {
				$location = $first['headers']['location'];
			}
			$location = is_array( $location ) ? (string) end( $location ) : (string) $location;
			if ( 0 === strpos( $location, 'https://' ) ) {
				$second = wp_safe_remote_get(
					$location,
					array(
						'timeout'  => 180,
						'stream'   => true,
						'filename' => $tmp,
					)
				);
				$ok     = ! is_wp_error( $second ) && 200 === (int) wp_remote_retrieve_response_code( $second );
			}
		}

		if ( ! $ok || ! file_exists( $tmp ) || filesize( $tmp ) < 1024 ) {
			@unlink( $tmp ); // phpcs:ignore WordPress.PHP.NoSilencedErrors, WordPress.WP.AlternativeFunctions
			// This server could not fetch the file itself: send the browser straight to GitHub.
			// (Works for public repositories; a private repository needs the fetch above to succeed.)
			if ( ! empty( $file['link'] ) && 0 === strpos( $file['link'], 'https://github.com/' ) ) {
				wp_redirect( $file['link'] ); // phpcs:ignore WordPress.Security.SafeRedirect -- fixed github.com release URL.
				exit;
			}
			wp_die( esc_html__( 'The file could not be fetched right now. Please try again in a moment.', 'bwp-app-builder' ), '', array( 'response' => 502 ) );
		}

		while ( ob_get_level() ) {
			ob_end_clean();
		}
		nocache_headers();
		header( 'Content-Type: ' . ( 'android' === $kind ? 'application/vnd.android.package-archive' : 'application/octet-stream' ) );
		header( 'Content-Disposition: attachment; filename="' . sanitize_file_name( $file['name'] ) . '"' );
		header( 'Content-Length: ' . filesize( $tmp ) );
		header( 'X-Content-Type-Options: nosniff' );
		readfile( $tmp ); // phpcs:ignore WordPress.WP.AlternativeFunctions
		@unlink( $tmp ); // phpcs:ignore WordPress.PHP.NoSilencedErrors, WordPress.WP.AlternativeFunctions
		exit;
	}

	/* ------------------------------------------------------------------ front end */

	public function shortcode() {
		if ( ! $this->can_use() ) {
			$s = $this->settings();
			if ( 'logged_in' === $s['access'] && ! is_user_logged_in() ) {
				return '<div class="bwpab bwpab-locked"><p>' . sprintf(
					/* translators: %s: login URL */
					wp_kses( __( 'Please <a href="%s">log in</a> to build an app.', 'bwp-app-builder' ), array( 'a' => array( 'href' => array() ) ) ),
					esc_url( wp_login_url( get_permalink() ) )
				) . '</p></div>';
			}
			return '';
		}

		$base = plugin_dir_url( __FILE__ ) . 'assets/';
		wp_enqueue_style( 'bwp-app-builder', $base . 'builder.css', array(), self::VERSION );
		wp_enqueue_script( 'bwp-app-builder', $base . 'builder.js', array(), self::VERSION, true );
		$offered = $this->settings()['platforms'];
		wp_localize_script(
			'bwp-app-builder',
			'BWPAB',
			array(
				'ajax'      => admin_url( 'admin-ajax.php' ),
				'nonce'     => wp_create_nonce( self::NONCE ),
				'platforms' => $offered,
				'text'      => array(
					'starting'  => __( 'Starting the build...', 'bwp-app-builder' ),
					'queued'    => __( 'Waiting for a build machine...', 'bwp-app-builder' ),
					'building'  => __( 'Building your app. This usually takes 3 to 10 minutes - you can leave this page open.', 'bwp-app-builder' ),
					'done'      => __( 'Your app is ready.', 'bwp-app-builder' ),
					'failed'    => __( 'The app could not be built.', 'bwp-app-builder' ),
					'network'   => __( 'Connection problem. Still trying...', 'bwp-app-builder' ),
					'ios'       => __( 'Download iPhone app (IPA)', 'bwp-app-builder' ),
					'android'   => __( 'Download Android app (APK)', 'bwp-app-builder' ),
					'iosFail'   => __( 'The iPhone app could not be built.', 'bwp-app-builder' ),
					'andFail'   => __( 'The Android app could not be built.', 'bwp-app-builder' ),
					'again'     => __( 'Build another app', 'bwp-app-builder' ),
					'iosNote'   => __( 'The IPA is unsigned. Install it on your iPhone with a sideloading tool such as Sideloadly or AltStore and your Apple ID.', 'bwp-app-builder' ),
					'andNote'   => __( 'The APK is a test build. Open it on your Android phone to install it.', 'bwp-app-builder' ),
					'elapsed'   => __( 'Time:', 'bwp-app-builder' ),
				),
			)
		);

		ob_start();
		?>
		<div class="bwpab" data-bwpab>
			<form class="bwpab-form" data-bwpab-form enctype="multipart/form-data" novalidate>
				<div class="bwpab-field">
					<label for="bwpab-name"><?php esc_html_e( 'App name', 'bwp-app-builder' ); ?></label>
					<input id="bwpab-name" name="app_name" type="text" maxlength="30" required autocomplete="off" placeholder="<?php esc_attr_e( 'My Shop', 'bwp-app-builder' ); ?>">
				</div>
				<div class="bwpab-field">
					<label for="bwpab-url"><?php esc_html_e( 'Website address', 'bwp-app-builder' ); ?></label>
					<input id="bwpab-url" name="site_url" type="text" inputmode="url" required autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="https://example.com">
					<p class="bwpab-hint"><?php esc_html_e( 'The page the app opens first, for example your login page. The site must use https.', 'bwp-app-builder' ); ?></p>
				</div>
				<div class="bwpab-field">
					<label for="bwpab-logo"><?php esc_html_e( 'Logo', 'bwp-app-builder' ); ?></label>
					<input id="bwpab-logo" name="logo" type="file" accept="image/png,image/jpeg,image/webp">
					<p class="bwpab-hint"><?php esc_html_e( 'Square PNG, 1024 x 1024 px or larger works best. Without a logo a letter icon is used.', 'bwp-app-builder' ); ?></p>
				</div>

				<?php if ( 'both' === $offered ) : ?>
				<fieldset class="bwpab-field bwpab-choice">
					<legend><?php esc_html_e( 'Build for', 'bwp-app-builder' ); ?></legend>
					<label><input type="radio" name="platforms" value="both" checked> <?php esc_html_e( 'iPhone and Android', 'bwp-app-builder' ); ?></label>
					<label><input type="radio" name="platforms" value="ios"> <?php esc_html_e( 'iPhone only', 'bwp-app-builder' ); ?></label>
					<label><input type="radio" name="platforms" value="android"> <?php esc_html_e( 'Android only', 'bwp-app-builder' ); ?></label>
				</fieldset>
				<?php endif; ?>

				<details class="bwpab-more">
					<summary><?php esc_html_e( 'More options', 'bwp-app-builder' ); ?></summary>
					<div class="bwpab-field">
						<label for="bwpab-company"><?php esc_html_e( 'Company name (shown on the loading screen)', 'bwp-app-builder' ); ?></label>
						<input id="bwpab-company" name="company" type="text" maxlength="40" autocomplete="off">
					</div>
					<div class="bwpab-field">
						<label for="bwpab-appid"><?php esc_html_e( 'App ID', 'bwp-app-builder' ); ?></label>
						<input id="bwpab-appid" name="app_id" type="text" maxlength="100" autocomplete="off" placeholder="com.company.app" spellcheck="false">
						<p class="bwpab-hint"><?php esc_html_e( 'Leave empty to create it from the website address.', 'bwp-app-builder' ); ?></p>
					</div>
					<div class="bwpab-colors">
						<div class="bwpab-field">
							<label for="bwpab-brand"><?php esc_html_e( 'Brand colour', 'bwp-app-builder' ); ?></label>
							<input id="bwpab-brand" name="brand_color" type="color" value="#1f2937">
						</div>
						<div class="bwpab-field">
							<label for="bwpab-bg"><?php esc_html_e( 'Loading screen background', 'bwp-app-builder' ); ?></label>
							<input id="bwpab-bg" name="background_color" type="color" value="#ffffff">
						</div>
					</div>
				</details>

				<p class="bwpab-error" data-bwpab-error role="alert" hidden></p>
				<button type="submit" class="bwpab-button" data-bwpab-submit><?php esc_html_e( 'Build my app', 'bwp-app-builder' ); ?></button>
			</form>

			<div class="bwpab-progress" data-bwpab-progress hidden aria-live="polite">
				<div class="bwpab-spinner" data-bwpab-spinner aria-hidden="true"></div>
				<p class="bwpab-title" data-bwpab-title></p>
				<p class="bwpab-status" data-bwpab-status></p>
				<p class="bwpab-time" data-bwpab-time></p>
				<div class="bwpab-downloads" data-bwpab-downloads></div>
				<ul class="bwpab-notes" data-bwpab-notes></ul>
				<button type="button" class="bwpab-link" data-bwpab-again hidden></button>
			</div>
		</div>
		<?php
		return (string) ob_get_clean();
	}

	/* ------------------------------------------------------------------ admin */

	public function admin_menu() {
		add_options_page( 'BWP App Builder', 'App Builder', 'manage_options', 'bwp-app-builder', array( $this, 'admin_page' ) );
	}

	public function handle_connection_test() {
		if ( ! current_user_can( 'manage_options' ) ) {
			wp_die( esc_html__( 'Not allowed.', 'bwp-app-builder' ) );
		}
		check_admin_referer( 'bwpab_test' );
		$s = $this->settings();
		if ( ! $this->is_configured() ) {
			$message = 'error|Fill in owner, repository and token first, then save.';
		} else {
			$result = $this->github( 'GET', $this->repo_path() . '/actions/workflows/' . rawurlencode( $s['workflow'] ) );
			if ( ! is_wp_error( $result ) && 200 === $result['code'] && is_array( $result['body'] ) ) {
				$state   = isset( $result['body']['state'] ) ? $result['body']['state'] : '?';
				$message = 'active' === $state
					? 'ok|Connected. Workflow "' . ( isset( $result['body']['name'] ) ? $result['body']['name'] : $s['workflow'] ) . '" was found and is active.'
					: 'error|The workflow was found but its state is "' . $state . '". Enable it on the Actions tab of the repository.';
			} else {
				$message = 'error|GitHub answered: ' . $this->github_message( $result ) . '. Check owner, repository, workflow file and the token permissions.';
			}
		}
		set_transient( 'bwpab_test_' . get_current_user_id(), $message, 60 );
		wp_safe_redirect( admin_url( 'options-general.php?page=bwp-app-builder' ) );
		exit;
	}

	public function admin_page() {
		if ( ! current_user_can( 'manage_options' ) ) {
			return;
		}
		$s         = $this->settings();
		$name      = self::OPTION;
		$from_file = defined( 'BWP_APP_BUILDER_GITHUB_TOKEN' ) && BWP_APP_BUILDER_GITHUB_TOKEN;
		$test      = get_transient( 'bwpab_test_' . get_current_user_id() );
		if ( $test ) {
			delete_transient( 'bwpab_test_' . get_current_user_id() );
		}
		?>
		<div class="wrap">
			<h1>BWP App Builder</h1>
			<p>Add the form to any page with the shortcode <code>[bwp_app_builder]</code>. Each build runs in your GitHub repository (workflow <code>build-app.yml</code>) and takes about 3 to 10 minutes.</p>

			<?php if ( $test ) : ?>
				<?php list( $kind, $text ) = array_pad( explode( '|', $test, 2 ), 2, '' ); ?>
				<div class="notice notice-<?php echo 'ok' === $kind ? 'success' : 'error'; ?>"><p><?php echo esc_html( $text ); ?></p></div>
			<?php endif; ?>

			<form method="post" action="options.php">
				<?php settings_fields( 'bwp_app_builder' ); ?>
				<h2>GitHub connection</h2>
				<table class="form-table" role="presentation">
					<tr>
						<th scope="row"><label for="bwpab-owner">Repository owner</label></th>
						<td><input id="bwpab-owner" class="regular-text" name="<?php echo esc_attr( $name ); ?>[owner]" value="<?php echo esc_attr( $s['owner'] ); ?>" placeholder="your-github-user"></td>
					</tr>
					<tr>
						<th scope="row"><label for="bwpab-repo">Repository name</label></th>
						<td><input id="bwpab-repo" class="regular-text" name="<?php echo esc_attr( $name ); ?>[repo]" value="<?php echo esc_attr( $s['repo'] ); ?>" placeholder="builder2343"></td>
					</tr>
					<tr>
						<th scope="row"><label for="bwpab-workflow">Workflow file</label></th>
						<td><input id="bwpab-workflow" class="regular-text" name="<?php echo esc_attr( $name ); ?>[workflow]" value="<?php echo esc_attr( $s['workflow'] ); ?>">
						<p class="description">Normally <code>build-app.yml</code>.</p></td>
					</tr>
					<tr>
						<th scope="row"><label for="bwpab-branch">Branch</label></th>
						<td><input id="bwpab-branch" class="regular-text" name="<?php echo esc_attr( $name ); ?>[branch]" value="<?php echo esc_attr( $s['branch'] ); ?>"></td>
					</tr>
					<tr>
						<th scope="row"><label for="bwpab-token">Access token</label></th>
						<td>
							<?php if ( $from_file ) : ?>
								<p><strong>Set in wp-config.php</strong> (<code>BWP_APP_BUILDER_GITHUB_TOKEN</code>).</p>
							<?php else : ?>
								<input id="bwpab-token" class="regular-text" type="password" autocomplete="new-password" name="<?php echo esc_attr( $name ); ?>[token]" value="" placeholder="<?php echo '' !== $s['token'] ? esc_attr( 'Saved - leave empty to keep it' ) : 'github_pat_...'; ?>">
								<?php if ( '' !== $s['token'] ) : ?>
									<label style="margin-left:8px"><input type="checkbox" name="<?php echo esc_attr( $name ); ?>[remove_token]" value="1"> Remove the saved token</label>
								<?php endif; ?>
							<?php endif; ?>
							<p class="description">GitHub &rarr; Settings &rarr; Developer settings &rarr; Fine-grained tokens. Give it access to <strong>only this repository</strong> with the permissions <strong>Actions: Read and write</strong> and <strong>Contents: Read-only</strong>. The token is never shown again and never sent to visitors.</p>
						</td>
					</tr>
				</table>

				<h2>Who can build apps</h2>
				<table class="form-table" role="presentation">
					<tr>
						<th scope="row">Access</th>
						<td>
							<fieldset>
								<label><input type="radio" name="<?php echo esc_attr( $name ); ?>[access]" value="admin" <?php checked( $s['access'], 'admin' ); ?>> Administrators only</label><br>
								<label><input type="radio" name="<?php echo esc_attr( $name ); ?>[access]" value="logged_in" <?php checked( $s['access'], 'logged_in' ); ?>> Logged-in users</label><br>
								<label><input type="radio" name="<?php echo esc_attr( $name ); ?>[access]" value="public" <?php checked( $s['access'], 'public' ); ?>> Everyone (no login)</label>
							</fieldset>
							<p class="description">With "Everyone", anybody can start builds on your GitHub account, for any website. Keep the limits below low.</p>
						</td>
					</tr>
					<tr>
						<th scope="row">Apps offered</th>
						<td>
							<select name="<?php echo esc_attr( $name ); ?>[platforms]">
								<option value="both" <?php selected( $s['platforms'], 'both' ); ?>>iPhone (IPA) and Android (APK) - the visitor chooses</option>
								<option value="ios" <?php selected( $s['platforms'], 'ios' ); ?>>iPhone (IPA) only</option>
								<option value="android" <?php selected( $s['platforms'], 'android' ); ?>>Android (APK) only</option>
							</select>
						</td>
					</tr>
					<tr>
						<th scope="row"><label for="bwpab-daily">Builds per person per day</label></th>
						<td><input id="bwpab-daily" type="number" min="1" max="500" class="small-text" name="<?php echo esc_attr( $name ); ?>[daily_limit]" value="<?php echo esc_attr( $s['daily_limit'] ); ?>">
						<p class="description">Counted per user account, or per IP address for visitors. Administrators are not limited.</p></td>
					</tr>
					<tr>
						<th scope="row"><label for="bwpab-active">Builds running at the same time</label></th>
						<td><input id="bwpab-active" type="number" min="1" max="20" class="small-text" name="<?php echo esc_attr( $name ); ?>[max_active]" value="<?php echo esc_attr( $s['max_active'] ); ?>"></td>
					</tr>
				</table>
				<?php submit_button(); ?>
			</form>

			<form method="post" action="<?php echo esc_url( admin_url( 'admin-post.php' ) ); ?>">
				<input type="hidden" name="action" value="bwpab_test">
				<?php wp_nonce_field( 'bwpab_test' ); ?>
				<?php submit_button( 'Test the GitHub connection', 'secondary', 'submit', false ); ?>
				<span class="description" style="margin-left:8px">Save the settings first.</span>
			</form>

			<h2 style="margin-top:2em">Recent builds</h2>
			<?php $this->render_builds_table(); ?>
		</div>
		<?php
	}

	private function render_builds_table() {
		$posts = get_posts(
			array(
				'post_type'        => self::POST_TYPE,
				'post_status'      => 'private',
				'posts_per_page'   => 25,
				'suppress_filters' => true,
				'no_found_rows'    => true,
			)
		);
		if ( ! $posts ) {
			echo '<p>No builds yet.</p>';
			return;
		}
		$s = $this->settings();
		echo '<table class="widefat striped"><thead><tr><th>Date</th><th>App</th><th>Website</th><th>User</th><th>For</th><th>Status</th><th>Details</th></tr></thead><tbody>';
		foreach ( $posts as $post ) {
			$this->refresh( $post );
			$status = (string) get_post_meta( $post->ID, '_bwpab_status', true );
			$user   = $post->post_author ? get_userdata( (int) $post->post_author ) : null;
			$run    = (string) get_post_meta( $post->ID, '_bwpab_run', true );
			$files  = get_post_meta( $post->ID, '_bwpab_files', true );
			$detail = array();
			foreach ( is_array( $files ) ? $files : array() as $file ) {
				$detail[] = esc_html( $file['name'] );
			}
			$notes = array_filter( array_merge( array( (string) get_post_meta( $post->ID, '_bwpab_error', true ) ), (array) get_post_meta( $post->ID, '_bwpab_errors', true ), (array) get_post_meta( $post->ID, '_bwpab_warnings', true ) ) );
			foreach ( $notes as $note ) {
				$detail[] = esc_html( $note );
			}
			if ( '' !== $run ) {
				$detail[] = '<a href="' . esc_url( 'https://github.com/' . $s['owner'] . '/' . $s['repo'] . '/actions/runs/' . $run ) . '" target="_blank" rel="noopener">GitHub log</a>';
			}
			printf(
				'<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td><strong>%s</strong></td><td>%s</td></tr>',
				esc_html( get_the_date( 'Y-m-d H:i', $post ) ),
				esc_html( $post->post_title ),
				esc_html( (string) get_post_meta( $post->ID, '_bwpab_url', true ) ),
				esc_html( $user ? $user->user_login : 'visitor' ),
				esc_html( (string) get_post_meta( $post->ID, '_bwpab_platforms', true ) ),
				esc_html( $status ),
				wp_kses( implode( '<br>', $detail ), array( 'br' => array(), 'a' => array( 'href' => array(), 'target' => array(), 'rel' => array() ) ) )
			);
		}
		echo '</tbody></table>';
	}

	/* ------------------------------------------------------------------ housekeeping */

	/** Daily: remove old build records and their uploaded logos. The files on GitHub are removed by the workflow. */
	public function cleanup() {
		$posts = get_posts(
			array(
				'post_type'        => self::POST_TYPE,
				'post_status'      => 'any',
				'posts_per_page'   => 200,
				'suppress_filters' => true,
				'no_found_rows'    => true,
				'date_query'       => array( array( 'before' => self::KEEP_DAYS . ' days ago' ) ),
			)
		);
		foreach ( $posts as $post ) {
			self::delete_logo( (string) get_post_meta( $post->ID, '_bwpab_logo', true ) );
			wp_delete_post( $post->ID, true );
		}
	}

	public static function delete_logo( $path ) {
		if ( '' === $path ) {
			return;
		}
		$uploads = wp_upload_dir();
		$folder  = wp_normalize_path( trailingslashit( $uploads['basedir'] ) . 'bwp-app-builder/' );
		$path    = wp_normalize_path( $path );
		// Only ever delete inside the plugin's own upload folder.
		if ( 0 === strpos( $path, $folder ) && false === strpos( $path, '..' ) && file_exists( $path ) ) {
			wp_delete_file( $path );
		}
	}
}

register_activation_hook( __FILE__, array( 'BWP_App_Builder', 'activate' ) );
register_deactivation_hook( __FILE__, array( 'BWP_App_Builder', 'deactivate' ) );
BWP_App_Builder::instance();
