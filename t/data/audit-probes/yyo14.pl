use POSIX qw(floor ceil fmod); print floor(3.7), ceil(3.2), floor(-3.5), ceil(-3.5), fmod(10, 3), " ", POSIX::strtol("ff", 16), " ", POSIX::INT_MAX, "\n";
