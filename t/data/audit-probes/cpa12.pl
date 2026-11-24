sub f { my ($r)=@_; my %c=%$r; $c{a}=5; return $r->{a} } my %h=(a=>1); print f(\%h), " $h{a}\n";
