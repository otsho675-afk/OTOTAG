<?php
function adminPartListings($pdo,$input) {
    $query=trim($input['q'] ?? '');
    $cursor=$input['before_id'] ?? '0';
    if (strlen($query)>200 || !preg_match('/^[0-9]{1,10}$/D',(string)$cursor)) throw new InvalidArgumentException('Arama veya sayfa bilgisi geçersiz.');
    $conditions=[]; $params=[];
    if ((int)$cursor>0) { $conditions[]='p.id<?'; $params[]=(int)$cursor; }
    if ($query!=='') { $conditions[]='(p.part_name LIKE ? OR p.car_model LIKE ? OR p.id=?)'; $params[]='%'.$query.'%'; $params[]='%'.$query.'%'; $params[]=ctype_digit($query) ? (int)$query : 0; }
    $where=$conditions ? ' WHERE '.implode(' AND ',$conditions) : '';
    $stmt=$pdo->prepare('SELECT p.*,u.name AS customer_name,u.phone AS customer_phone,s.name AS seller_name,s.phone AS seller_phone FROM part_listings p LEFT JOIN users u ON u.id=p.customer_id LEFT JOIN users s ON s.id=p.seller_id'.$where.' ORDER BY p.id DESC LIMIT 101');
    $stmt->execute($params); $rows=$stmt->fetchAll(PDO::FETCH_ASSOC); $more=count($rows)>100;
    if ($more) array_pop($rows);
    return ['status'=>'success','market'=>$rows,'has_more'=>$more,'next_cursor'=>$more ? (int)$rows[count($rows)-1]['id'] : null];
}
