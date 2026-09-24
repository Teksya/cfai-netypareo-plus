package fr.babouins.netypareo_plus

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * Widget "Prochain cours" : le cours en cours ou le suivant, avec l'horaire et la salle.
 *
 * L'application (et la synchronisation en arrière-plan) y dépose les cours des prochains jours
 * sous la clé `seances` ; le choix du cours à afficher se fait ici, à chaque mise à jour, pour
 * rester juste sans que l'application tourne. Les mises à jour sont programmées par l'application
 * aux débuts et fins de cours.
 */
class NextCourseWidget : HomeWidgetProvider() {

  private data class Course(val subject: String, val start: Long, val end: Long, val room: String)

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val courses = read(widgetData)
    for (id in appWidgetIds) {
      val views = RemoteViews(context.packageName, R.layout.widget_next_course)
      render(views, courses, System.currentTimeMillis())
      views.setOnClickPendingIntent(
          R.id.widget_root,
          HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
      )
      appWidgetManager.updateAppWidget(id, views)
    }
  }

  private fun read(prefs: SharedPreferences): List<Course> {
    val raw = prefs.getString("seances", null) ?: return emptyList()
    return try {
      val array = JSONArray(raw)
      (0 until array.length())
          .map { array.getJSONObject(it) }
          .map { Course(it.getString("s"), it.getLong("a"), it.getLong("b"), it.optString("r")) }
          .sortedBy { it.start }
    } catch (e: Exception) {
      emptyList()
    }
  }

  private fun render(views: RemoteViews, courses: List<Course>, now: Long) {
    val hm = SimpleDateFormat("HH:mm", Locale.FRANCE)
    val current = courses.firstOrNull { it.start <= now && now < it.end }
    val shown = current ?: courses.firstOrNull { it.start > now }

    if (shown == null) {
      views.setTextViewText(R.id.widget_label, "NetYParéo+")
      views.setTextViewText(R.id.widget_subject, "Aucun cours prévu")
      views.setTextViewText(R.id.widget_details, "Rien dans les prochains jours.")
      views.setViewVisibility(R.id.widget_next, View.GONE)
      return
    }

    views.setTextViewText(R.id.widget_label, label(shown, current != null, now, hm))
    views.setTextViewText(R.id.widget_subject, shown.subject)
    val time = "${hm.format(shown.start)} – ${hm.format(shown.end)}"
    views.setTextViewText(R.id.widget_details, if (shown.room.isEmpty()) time else "$time · ${shown.room}")

    val after = courses.firstOrNull { it.start >= shown.end && sameDay(it.start, shown.start) }
    if (after == null) {
      views.setViewVisibility(R.id.widget_next, View.GONE)
    } else {
      views.setViewVisibility(R.id.widget_next, View.VISIBLE)
      views.setTextViewText(R.id.widget_next, "Ensuite : ${hm.format(after.start)} ${after.subject}")
    }
  }

  private fun label(course: Course, ongoing: Boolean, now: Long, hm: SimpleDateFormat): String {
    if (ongoing) return "EN COURS · JUSQU'À ${hm.format(course.end)}"
    val minutes = (course.start - now) / 60000
    if (sameDay(course.start, now)) {
      return if (minutes < 60) "DANS ${minutes + 1} MIN" else "PROCHAIN COURS"
    }
    val tomorrow = Calendar.getInstance().apply {
      timeInMillis = now
      add(Calendar.DAY_OF_YEAR, 1)
    }
    if (sameDay(course.start, tomorrow.timeInMillis)) return "DEMAIN"
    return SimpleDateFormat("EEEE d MMMM", Locale.FRANCE).format(course.start).uppercase(Locale.FRANCE)
  }

  private fun sameDay(a: Long, b: Long): Boolean {
    val ca = Calendar.getInstance().apply { timeInMillis = a }
    val cb = Calendar.getInstance().apply { timeInMillis = b }
    return ca.get(Calendar.YEAR) == cb.get(Calendar.YEAR) &&
        ca.get(Calendar.DAY_OF_YEAR) == cb.get(Calendar.DAY_OF_YEAR)
  }
}
