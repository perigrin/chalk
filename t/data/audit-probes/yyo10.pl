use Time::Local qw(timegm); print timegm(0, 0, 0, 1, 0, 2000), " ", timegm(59, 59, 23, 31, 11, 1999), "\n";
