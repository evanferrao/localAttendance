import 'package:face_att/models/attendance_record.dart';
import 'package:face_att/utils/app_colors.dart';
import 'package:face_att/utils/utils.dart';
import 'package:flutter/material.dart';

/// Tab bar and views displaying live present/absent student lists for attendance scanner
class ScannerStudentTabs extends StatelessWidget {
  final TabController tabController;
  final List<AttendanceRecord> presentList;
  final List<AttendanceRecord> absentList;

  const ScannerStudentTabs({
    super.key,
    required this.tabController,
    required this.presentList,
    required this.absentList,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        TabBar(
          controller: tabController,
          indicatorColor: colorScheme.primary,
          indicatorWeight: 2.5,
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          dividerColor: colorScheme.outlineVariant.withValues(alpha: 0.2),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          tabs: [
            Tab(text: "Present (${presentList.length})"),
            Tab(text: "Absent (${absentList.length})"),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: tabController,
            children: [
              // Present List
              presentList.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.how_to_reg_outlined,
                              size: 40,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "No students marked present yet",
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Point the camera at students to mark attendance",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: presentList.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: colorScheme.outlineVariant.withValues(alpha: 0.15),
                      ),
                      itemBuilder: (_, i) {
                        final r = presentList[i];
                        final initial = StringUtils.initials(r.studentName);
                        final timeStr = DateTimeUtils.formatTimeShort(r.attendanceTime);

                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.present.withValues(alpha: 0.15),
                            child: Text(
                              initial,
                              style: const TextStyle(
                                color: AppColors.present,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          title: Text(
                            r.studentName,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            r.studentRegisterNumber,
                            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (timeStr.isNotEmpty)
                                Text(
                                  timeStr,
                                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                                ),
                              const SizedBox(width: 6),
                              const Icon(Icons.check_circle_rounded, color: AppColors.present, size: 18),
                            ],
                          ),
                        );
                      },
                    ),

              // Absent List
              absentList.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.celebration_rounded, size: 40, color: AppColors.present),
                            const SizedBox(height: 10),
                            const Text(
                              "All students marked present!",
                              style: TextStyle(
                                color: AppColors.present,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: absentList.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: colorScheme.outlineVariant.withValues(alpha: 0.15),
                      ),
                      itemBuilder: (_, i) {
                        final r = absentList[i];
                        final initial = StringUtils.initials(r.studentName);

                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: colorScheme.surfaceContainerHighest,
                            child: Text(
                              initial,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          title: Text(
                            r.studentName,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            r.studentRegisterNumber,
                            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.absent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.absent.withValues(alpha: 0.25)),
                            ),
                            child: const Text(
                              "Absent",
                              style: TextStyle(
                                color: AppColors.absent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ],
          ),
        ),
      ],
    );
  }
}
