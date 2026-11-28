use feature 'try'; no warnings; our $g = 1; try { local $g = 2; die "z\n" } catch ($e) { print $g } print "$g\n";
