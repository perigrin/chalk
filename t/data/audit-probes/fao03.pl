package P; sub new { my ($c,%a)=@_; my $s=bless {%a}, $c; $a{x}=99; $s } package main; my $o=P->new(x=>1); print $o->{x},"\n";
