my %h=(a=>1); my $f=sub { my %c=%h; $c{a}++; $c{a} }; $f->(); print $f->(), $h{a}, "\n";
