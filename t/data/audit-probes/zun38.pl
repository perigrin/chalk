use strict; our $g=1; eval { local $g=2; my @a=("s"); my $x=$a[0]->{k}; }; print "$g ", ($@ ? "died" : "ok"), "\n";
