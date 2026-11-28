my %h = (a=>1); sub ch { $_[0]{a} = 2 } ch(\%h); sub cp { my %c = %{$_[0]}; $c{a} = 3 } cp(\%h); print $h{a}, "\n";
