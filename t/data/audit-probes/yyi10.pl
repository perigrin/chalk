sub inc { $_[0]++ } my ($z,$y)=(undef,5); inc($z // $y); print defined $z ? $z : "u", " $y\n";
