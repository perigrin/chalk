our $g = 1; my @v = map { local $g = $_; $g } 5, 6; print "$g @v\n";
