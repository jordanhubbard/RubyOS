/* langinfo.h — bare-metal stub for PythonOS. */
#pragma once

/* nl_item values for nl_langinfo() */
#define CODESET      14
#define D_T_FMT      15
#define D_FMT        16
#define T_FMT        17
#define T_FMT_AMPM   18
#define AM_STR       19
#define PM_STR       20

/* Day names (Sunday=1) */
#define DAY_1        33
#define DAY_2        34
#define DAY_3        35
#define DAY_4        36
#define DAY_5        37
#define DAY_6        38
#define DAY_7        39

/* Abbreviated day names */
#define ABDAY_1      40
#define ABDAY_2      41
#define ABDAY_3      42
#define ABDAY_4      43
#define ABDAY_5      44
#define ABDAY_6      45
#define ABDAY_7      46

/* Month names */
#define MON_1        47
#define MON_2        48
#define MON_3        49
#define MON_4        50
#define MON_5        51
#define MON_6        52
#define MON_7        53
#define MON_8        54
#define MON_9        55
#define MON_10       56
#define MON_11       57
#define MON_12       58

/* Abbreviated month names */
#define ABMON_1      59
#define ABMON_2      60
#define ABMON_3      61
#define ABMON_4      62
#define ABMON_5      63
#define ABMON_6      64
#define ABMON_7      65
#define ABMON_8      66
#define ABMON_9      67
#define ABMON_10     68
#define ABMON_11     69
#define ABMON_12     70

#define ERA          45
#define ERA_D_FMT    46
#define ERA_D_T_FMT  47
#define ERA_T_FMT    48
#define ALT_DIGITS   49
#define RADIXCHAR    50
#define THOUSEP      51
#define YESEXPR      52
#define NOEXPR       53
#define CRNCYSTR     56

typedef int nl_item;
char *nl_langinfo(nl_item item);
