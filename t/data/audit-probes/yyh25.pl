sub f { my %h=(a=>1,b=>2); %h } sub g { my %h=(a=>1); return %h } my $n=f(); my @l=g(); print "$n@l\n";
