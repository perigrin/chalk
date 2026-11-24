use feature 'try'; no warnings; my $e="outer"; try { die "in\n" } catch ($e) { } print "$e\n";
