my %h=(a=>1,b=>2); %h=(b=>$h{a},a=>$h{b}); print "$h{a}$h{b}\n";
