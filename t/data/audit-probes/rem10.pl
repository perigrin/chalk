package C; sub new { my %a=(n=>1); bless \%a, shift } package main; my $o=C->new; my $p=C->new; $o->{n}=5; print $p->{n},"\n";
