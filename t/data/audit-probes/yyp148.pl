our $g=1; my $f = sub { "@_" }; print $f->($g, $g++), "\n";
