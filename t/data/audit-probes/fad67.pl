our $g=1; sub f { local $g=2; my $h=$_[0]; $h->{a}{b} } use strict; eval { f({a=>"str"}) }; print "$g\n";
