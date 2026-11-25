use strict; our $g=1; eval { local $g=2; my $r; my @x=@$r; }; print "$g ", ($@ ? "died" : "ok"), "\n";
