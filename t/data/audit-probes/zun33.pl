our $g=1; eval { local $g=2; my $z=0; my $q=1/$z; }; print "$g ", ($@ ? "died" : "ok"), "\n";
