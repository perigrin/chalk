sub f { my %o=@_; $o{a}=9; return $o{a} } my %h=(a=>1); f(%h); print "$h{a}\n";
