<?php
/**
 * BWP App Builder - removes its settings, build records and uploaded logos when the plugin is deleted.
 */

if ( ! defined( 'WP_UNINSTALL_PLUGIN' ) ) {
	exit;
}

delete_option( 'bwp_app_builder_settings' );
wp_clear_scheduled_hook( 'bwp_app_builder_cleanup' );

$bwpab_posts = get_posts(
	array(
		'post_type'        => 'bwp_app_build',
		'post_status'      => 'any',
		'posts_per_page'   => -1,
		'fields'           => 'ids',
		'suppress_filters' => true,
	)
);
foreach ( $bwpab_posts as $bwpab_post_id ) {
	wp_delete_post( $bwpab_post_id, true );
}

$bwpab_uploads = wp_upload_dir();
$bwpab_folder  = trailingslashit( $bwpab_uploads['basedir'] ) . 'bwp-app-builder';
if ( is_dir( $bwpab_folder ) ) {
	foreach ( (array) glob( $bwpab_folder . '/logo-*' ) as $bwpab_file ) {
		if ( is_file( $bwpab_file ) ) {
			wp_delete_file( $bwpab_file );
		}
	}
	@rmdir( $bwpab_folder ); // phpcs:ignore WordPress.PHP.NoSilencedErrors, WordPress.WP.AlternativeFunctions
}
