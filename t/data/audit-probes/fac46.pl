sub cp { my %o=%{$_[0]}; $o{x}=1; \%o } my %h=(a=>1); my $r=cp(\%h); print exists $h{x}?1:0, exists $r->{a}?1:0, "\n";
