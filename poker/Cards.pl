
package Cards;


use MSSQL::Sqllib;
use strict;

use vars qw / %Vc %Vl %Val @RevGroup %Group @PosDef/ ;

%Vc = ( A => 14, K => 13, Q => 12, J => 11, T => 10 );
map { $Vc{$_} = $_ } (2..9);
%Vl = qw / s 1 h 2 d 3 c 4 /;
map { my $c = $_; map { $Val{"$c$_"} = "$Vc{$c}.$Vl{$_}" + 0 } qw(s h d c) } keys %Vc;

my @k = keys %Val;

@PosDef = ( [qw/S B/],
	    [qw/S B L/],
	    [qw/S B M L/],
	    [qw/S B E M L/],
	    [qw/S B E E M L/], # could see if pos 4 could be M instead
	    [qw/S B E E M M L/],
	    [qw/S B E E M M L L/],
	    [qw/S B E E E M M L L/],
	    [qw/S B E E E M M M L L/]);

my @RevGroup = ( [ qw/ AA KK QQ JJ AKs/ ],
		 [ qw/ TT AQs AJs KQs AKo/ ],
		 [ qw/ 99 JTs QJs KJs ATs AQo/ ],
		 [ qw/ T9s KQo 88 QTs 98s J9s AJo KTs/ ],
		 [ qw/ 77 87s Q9s T8s KJo QJo JTo 76s 97s A9s A8s A7s A6s A5s A4s A3s A2s 65s/ ],
		 [ qw/ 66 ATo 55 86s KTo QTo 54s K9s J8s 75s/ ],
		 [ qw/ 44 J9o 64s T9o 53s 33 98o 43s 22 K8s K7s K6s K5s K4s K3s K2s T7s Q8s/ ],
		 [ qw/ 87o A9o Q9o 76o 42s 32s 96s 85s J8o J7s 65o 54o 74s K9o T8o/ ]);

map { my $g = $_; map { $Group{$_} = $g+1 } @{$RevGroup[$_]} } (0..7);


sub SortCards { sort { $Val{$b} <=> $Val{$a}  } @_ }

sub NewFlop {
    my @cards = SortCards(@_);
    
    my @vals = map { $Val{$_} } @cards;
    ::Debug ("Cards: [@_] -> [@cards] [@vals]\n");
    my @res = sql("select FlopID from Flops 
                                 where C1 = '$cards[0]' and
                                       C2 = '$cards[1]' and
                                       C3 = '$cards[2]'");
    unless ($res[0]->{FlopID}) {
		sql("insert into Flops values ('$cards[0]', '$cards[1]', '$cards[2]')");
		@res = sql("select FlopID from Flops 
                                 where C1 = '$cards[0]' and
                                       C2 = '$cards[1]' and
                                       C3 = '$cards[2]'");
		::Debug("New flop $res[0]->{FlopID} for [@cards]\n");
    }
    $res[0]->{FlopID};
}

sub HandRef {
    my ($c1, $c2) = SortCards @_;

    "$c1 $c2" =~ /(.)(.) (.)(.)/;
    if ($1 eq $3) {
		::Debug (" HR(@_) : [$c1 $c2] -> $1$1  ($2 $3 $4)\n");
		return "$1$1";
    } elsif ($2 eq $4) {
		::Debug (" HR(@_) : [$c1 $c2] -> $1$3s  ($2 $4)\n");
		return "$1$3s";
    } 
    ::Debug (" HR(@_) : [$c1 $c2] -> $1$3o  ($2 $4)\n");
    return "$1$3o";
}

1;
