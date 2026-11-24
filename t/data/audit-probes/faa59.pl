my %h=(a=>1); %h=map { $_=>$h{$_}+1 } keys %h; print "$h{a}\n";
