concrete BikeEng of Bike = ActionEng ** open
  Prelude,
  ParadigmsEng,
  SyntaxEng,
  SymbolicEng,
  (WN=WordNetEng) in {
  lin
    -- : Action_Dir ;
    Send = mkDir send_V2 ;
    Deliver = mkDir deliver_V2 ;
    Receive = mkDir receive_V2 ;

    -- : Kind ;
    Order = kind "order" ;
    Delivery = kind "delivery" ;
    Payment = kind "payment" ;
    Bike = kind "bike" ;
    Item = kind "item" ;
    Inventory = kind "inventory" ;

    -- : Int -> Term ;
    Eur int =
      let n : Det = mkDet <symb (mkSymb int.s) : Card> ;
       in mkNP n (mkN "EUR" "EUR") ;

  oper
    send_V2 : V2 = <WN.send_V3 : V2> ;
    deliver_V2 : V2 = mkV2 WN.deliver_2_V ;
    receive_V2 : V2 = WN.receive_1_V2 ;

}