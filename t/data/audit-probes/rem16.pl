sub mk { my %o=(a=>1); return \%o } my $p=mk(); my $q=mk(); $p->{a}=2; print $q->{a},"\n";
