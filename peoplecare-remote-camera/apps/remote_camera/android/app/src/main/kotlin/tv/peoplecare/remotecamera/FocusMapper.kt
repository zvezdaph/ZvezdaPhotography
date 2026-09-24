package tv.peoplecare.remotecamera

/**
 * Converts a point of the transmitted (upright) frame into normalized sensor
 * coordinates. The frame shown to viewers is the sensor image rotated
 * clockwise by [rotationDegrees] (and mirrored for front cameras when
 * [mirrored] is true).
 */
object FocusMapper {
    data class Point(val x: Float, val y: Float)

    fun frameToSensor(x: Float, y: Float, rotationDegrees: Int, mirrored: Boolean): Point {
        val fx = if (mirrored) 1f - x else x
        val r = ((rotationDegrees % 360) + 360) % 360
        val p = when (r) {
            90 -> Point(y, 1f - fx)
            180 -> Point(1f - fx, 1f - y)
            270 -> Point(1f - y, fx)
            else -> Point(fx, y)
        }
        return Point(p.x.coerceIn(0f, 1f), p.y.coerceIn(0f, 1f))
    }

    /**
     * Rotation between sensor and the upright frame, as defined by the Camera2
     * documentation for CameraCharacteristics.SENSOR_ORIENTATION.
     */
    fun sensorToFrameRotation(sensorOrientation: Int, displayRotationDegrees: Int, front: Boolean): Int =
        if (front) (sensorOrientation + displayRotationDegrees) % 360
        else (sensorOrientation - displayRotationDegrees + 360) % 360
}
