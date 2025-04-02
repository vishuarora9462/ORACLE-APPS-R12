CREATE OR REPLACE PROCEDURE APPS.xxmssl_inv_seq_gen_me_prc (
   errbuf       OUT      VARCHAR2,
   retcode      OUT      NUMBER  ,
   p_delivery   IN       NUMBER
)
IS
   CURSOR c1 (p_organization_id NUMBER, p_delivery_id NUMBER)
   IS
      SELECT *
        FROM wsh_new_deliveries wd
       WHERE attribute8 IS NULL
         AND delivery_id = p_delivery_id
         AND organization_id = p_organization_id
         AND EXISTS (
                SELECT 1
                  FROM oe_order_headers_all ooha,
                       oe_order_lines_all oola,
                       oe_transaction_types_all ott,
                       wsh_new_deliveries wnd,
                       wsh_delivery_assignments wda,
                       wsh_delivery_details wdd,
                       xle_entity_profiles xep,
                       fnd_lookup_values flv,
                       hr_operating_units hou
                 WHERE wdd.source_header_id = ooha.header_id
                   AND wdd.source_line_id = oola.line_id
                   AND ooha.header_id = oola.header_id
                   AND wdd.delivery_detail_id = wda.delivery_detail_id
                   AND wnd.delivery_id = wda.delivery_id
                   AND ott.transaction_type_id = ooha.order_type_id
                   AND wnd.delivery_id = wd.delivery_id
                   AND wnd.organization_id = wd.organization_id
                   AND flv.meaning = xep.NAME
                   AND hou.default_legal_context_id = xep.legal_entity_id
                   AND flv.lookup_type = 'XXMSSL_OM_INV_REPORT_LEG_ENT'
                   AND ooha.org_id = hou.organization_id);

   lv_attribute         VARCHAR2 (240);
   ln_organization_id   NUMBER;
   lv_org_code          VARCHAR2 (10);
   lv_sequence_id       NUMBER;
   lv_sequence_no       VARCHAR2 (250);
   ln_count             NUMBER;
   v_confirm_date       wsh_new_deliveries.CONFIRM_DATE%TYPE;--pratik 
   v_self_b_inv         NUMBER;--pratik 
   v_attribute8         NUMBER;--pratik 
BEGIN

     
       SELECT wnd.attribute8, wnd.organization_id, ood.organization_code , confirm_date --pratik 
         INTO lv_attribute, ln_organization_id, lv_org_code              , v_confirm_date--pratik 
         FROM wsh_new_deliveries wnd, org_organization_definitions ood
        WHERE 1 = 1
          AND wnd.organization_id = ood.organization_id
          AND wnd.delivery_id = p_delivery;
  
   dbms_output.put_line('1. lv_attribute:'||lv_attribute||', ln_organization_id:'||ln_organization_id||', lv_org_code:'||lv_org_code||', v_confirm_date:'||v_confirm_date);
   
    
   fnd_file.put_line (fnd_file.LOG,
                         'Updating Delivery ID '
                      || p_delivery
                      || ', Existing Inv No:'
                      || lv_attribute
                      || ' for Organization: '
                      || ln_organization_id
                     );
   --pratik 
    select count(1) 
      INTO v_self_b_inv--wnd.ATTRIBUTE8,wnd.ATTRIBUTE9,confirm_date 
      from wsh_new_deliveries       wnd,
           wsh_delivery_assignments wda,
           wsh_delivery_details     wdd 
     where wnd.delivery_id        = wda.delivery_id 
       AND wda.delivery_detail_id = wdd.delivery_detail_id
       AND wnd.delivery_id        = p_delivery --484698
       AND EXISTS (SELECT 1 
                     FROM OE_TRANSACTION_TYPES_ALL ott 
                    WHERE ott.transaction_type_id = wdd.source_header_type_id 
                      AND ott.attribute2 = 'DELIVERY'
                      AND ott.attribute3 = 'SALE'
                      AND ott.attribute4 = 'INVOICE'
                   ) ;
   IF v_self_b_inv <= 0 THEN 
    
  --end pratik 
       SELECT xdsnl.sequence_id
         INTO lv_sequence_id
         FROM oe_transaction_types_tl ott,
              wsh_delivery_details wdd,
              wsh_delivery_assignments wda,
              wsh_new_deliveries wnd,
              xxmssl_doc_seq_no_lines xdsnl,
              mtl_parameters mp                                     -- Changes by SankaraNarayana As on 31MAY24 MD50 V1.1
        WHERE ott.transaction_type_id = wdd.source_header_type_id
          AND wdd.delivery_detail_id = wda.delivery_detail_id
          AND wda.delivery_id = wnd.delivery_id
          AND xdsnl.document_category = ott.NAME
          AND xdsnl.INVENTORY_ORG = mp.organization_code            -- Changes by SankaraNarayana As on 31MAY24 MD50 V1.1
          and mp.organization_id = wnd.organization_id              -- Changes by SankaraNarayana As on 31MAY24 MD50 V1.1
          AND wnd.delivery_id = p_delivery
          AND wnd.organization_id = ln_organization_id
          AND TRUNC(SYSDATE) BETWEEN xdsnl.from_date AND xdsnl.TO_DATE
          AND ROWNUM = 1;
      
   END IF; -- added pratik 
   dbms_output.put_line('lv_sequence_id:'||lv_sequence_id);
   
   IF lv_attribute IS NULL
   THEN
     IF v_self_b_inv <= 0 THEN -- added pratik  
      FOR i IN c1 (ln_organization_id, p_delivery)
          LOOP
            
             BEGIN
                SELECT NVL (current_no, start_no) + 1
                  INTO lv_sequence_no
                  FROM xxmssl_doc_seq_no_header
                 WHERE sequence_id = lv_sequence_id;

                fnd_file.put_line (fnd_file.LOG,
                                   'Sequence Number generated:' || lv_sequence_no
                                  );
                dbms_output.put_line('lv_sequence_no:'||lv_sequence_no);
             EXCEPTION
                WHEN NO_DATA_FOUND
                THEN
                   lv_sequence_no := '000001';
                   fnd_file.put_line (fnd_file.LOG,
                                      'Sequence Number :' || lv_sequence_no
                                     );
                  dbms_output.put_line('Exception Sequence Number :' || lv_sequence_no);                    
             END;

             BEGIN
                SELECT COUNT (*)
                  INTO ln_count
                  FROM wsh_new_deliveries
                 WHERE attribute8 = lv_sequence_no;
               dbms_output.put_line('ln_count:' || ln_count);
               
                IF ln_count = 0
                THEN
                   UPDATE wsh_new_deliveries a
                      SET attribute8 = lv_sequence_no,
                          attribute9 = TO_CHAR (SYSDATE, 'RRRR/MM/DD HH24:MI:SS')
                    WHERE delivery_id = p_delivery
                      AND NOT EXISTS (
                             SELECT 1
                               FROM wsh_new_deliveries b
                              WHERE a.delivery_id <> b.delivery_id
                                AND b.attribute8 = lv_sequence_no);
                dbms_output.put_line('RowUpdated1:' || SQL%ROWCOUNT); 
                   UPDATE xxmssl_doc_seq_no_header
                      SET current_no = lv_sequence_no
                    WHERE sequence_id = lv_sequence_id;
                dbms_output.put_line('RowUpdated2:' || SQL%ROWCOUNT); 
                   COMMIT;
                   fnd_file.put_line (fnd_file.LOG,
                                      'Updated Delivery ID:' || p_delivery
                                     );
                ELSIF ln_count = 1
                THEN
                   fnd_file.put_line (fnd_file.LOG,
                                      'Invoice number exits already'
                                     );
                ELSE
                   fnd_file.put_line (fnd_file.LOG,
                                         'Updating Delivery ID:'
                                      || p_delivery
                                      || ' waiting for other delivery'
                                     );
                END IF;
             EXCEPTION
                WHEN OTHERS
                THEN
                   retcode := 2;
                   DBMS_OUTPUT.put_line
                                      (   'Error while updating Invoice number:'
                                       || SQLCODE
                                       || SQLERRM
                                      );
                   fnd_file.put_line (fnd_file.LOG,
                                         'Error while updating Invoice number:'
                                      || SQLCODE
                                      || SQLERRM
                                     );
             END;
          END LOOP;
     --start pratik 
     ELSE 
     
        SELECT count(x.attribute8) 
          INTO v_attribute8
          FROM wsh_new_deliveries x
         WHERE x.delivery_id = p_delivery 
           AND x.attribute8 IS NOT NULL ;
         
         IF v_attribute8 = 0 THEN 
         
          UPDATE wsh_new_deliveries a 
             SET a.attribute8 = p_delivery,
                 a.attribute9 = TO_CHAR (v_confirm_date, 'RRRR/MM/DD HH24:MI:SS')
           WHERE a.delivery_id = p_delivery ;
         
         ELSIF v_attribute8  = 1
                THEN
                DBMS_OUTPUT.put_line('Invoice number exits already'
                                     );  
                   fnd_file.put_line (fnd_file.LOG,
                                      'Invoice number exits already'
                                     );           
         END IF; 
     
           COMMIT;
           
     END IF; 
     -- end pratik 
   END IF;
END;
/
