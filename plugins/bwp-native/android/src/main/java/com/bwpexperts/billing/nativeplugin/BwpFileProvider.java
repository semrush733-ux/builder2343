package com.bwpexperts.billing.nativeplugin;

import androidx.core.content.FileProvider;

/** Own FileProvider so the plugin never clashes with another provider declared by the app. */
public class BwpFileProvider extends FileProvider {
}
