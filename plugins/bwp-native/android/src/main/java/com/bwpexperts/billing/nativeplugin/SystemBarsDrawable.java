package com.bwpexperts.billing.nativeplugin;

import android.graphics.Canvas;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.drawable.Drawable;

/**
 * Background of the web view container: paints the strip behind the status bar in one colour
 * and everything else (navigation bar / gesture area / side cut-outs) in another.
 */
class SystemBarsDrawable extends Drawable {

    private final Paint topPaint = new Paint();
    private final Paint restPaint = new Paint();
    private int topHeight = 0;

    SystemBarsDrawable(int topColor, int restColor) {
        topPaint.setColor(topColor);
        restPaint.setColor(restColor);
    }

    void setColors(int topColor, int restColor) {
        if (topPaint.getColor() != topColor || restPaint.getColor() != restColor) {
            topPaint.setColor(topColor);
            restPaint.setColor(restColor);
            invalidateSelf();
        }
    }

    void setTopHeight(int height) {
        if (height != topHeight) {
            topHeight = height;
            invalidateSelf();
        }
    }

    @Override
    public void draw(Canvas canvas) {
        Rect bounds = getBounds();
        int split = Math.min(bounds.bottom, bounds.top + topHeight);
        if (split > bounds.top) {
            canvas.drawRect(bounds.left, bounds.top, bounds.right, split, topPaint);
        }
        canvas.drawRect(bounds.left, split, bounds.right, bounds.bottom, restPaint);
    }

    @Override
    public void setAlpha(int alpha) {
        // always opaque
    }

    @Override
    public void setColorFilter(ColorFilter colorFilter) {
        // not used
    }

    @Override
    public int getOpacity() {
        return PixelFormat.OPAQUE;
    }
}
