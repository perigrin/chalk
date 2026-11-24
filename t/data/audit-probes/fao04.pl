my %def=(a=>1,b=>2); sub mk { my %o=(%def,@_); \%o } my $x=mk(a=>5); my $y=mk(); print "$x->{a}$y->{a}$def{a}\n";
