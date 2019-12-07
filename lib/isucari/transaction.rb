 get '/users/transactions.json' do
      user = get_user

      item_id = params['item_id'].to_i
      created_at = params['created_at'].to_i

      db.query('BEGIN')
      items = if item_id > 0 && created_at > 0
        # paging
        begin
          db.xquery("SELECT * FROM `items` WHERE (`seller_id` = ? OR `buyer_id` = ?) AND `status` IN (?, ?, ?, ?, ?) AND (`created_at` < ?  OR (`created_at` <= ? AND `id` < ?)) ORDER BY `created_at` DESC, `id` DESC LIMIT #{TRANSACTIONS_PER_PAGE + 1}", user['id'], user['id'], ITEM_STATUS_ON_SALE, ITEM_STATUS_TRADING, ITEM_STATUS_SOLD_OUT, ITEM_STATUS_CANCEL, ITEM_STATUS_STOP, Time.at(created_at), Time.at(created_at), item_id)
        rescue
          db.query('ROLLBACK')
          halt_with_error 500, 'db error'
        end
      else
        # 1st page
        begin
          db.xquery("SELECT * FROM `items` WHERE (`seller_id` = ? OR `buyer_id` = ?) AND `status` IN (?, ?, ?, ?, ?) ORDER BY `created_at` DESC, `id` DESC LIMIT #{TRANSACTIONS_PER_PAGE + 1}", user['id'], user['id'], ITEM_STATUS_ON_SALE, ITEM_STATUS_TRADING, ITEM_STATUS_SOLD_OUT, ITEM_STATUS_CANCEL, ITEM_STATUS_STOP)
        rescue
          db.query('ROLLBACK')
          halt_with_error 500, 'db error'
        end
      end

      user_list = db.query("SELECT * FROM `users` WHERE id in (?)",items.map{|item| [item['seller_id'],item['buyer_id']}.flatten.compact)
                      .map do |user|
                        {
                          'id' => user['id'],
                          'account_name' => user['account_name'],
                          'num_sell_items' => user['num_sell_items']
                        }
                      end 


      item_details = items.map do |item|
        seller = user_list.select{|seller| seller['id'] == item['seller_id']}.first
        if seller.nil?
          db.query('ROLLBACK')
          halt_with_error 404, 'seller not found'
        end

        category = get_category_by_id(item['category_id'])
        if category.nil?
          db.query('ROLLBACK')
          halt_with_error 404, 'category not found'
        end

        item_detail = {
          'id' => item['id'],
          'seller_id' => item['seller_id'],
          'seller' => seller,
          # buyer_id
          # buyer
          'status' => item['status'],
          'name' => item['name'],
          'price' => item['price'],
          'description' => item['description'],
          'image_url' => get_image_url(item['image_name']),
          'category_id' => item['category_id'],
          # transaction_evidence_id
          # transaction_evidence_status
          # shipping_status
          'category' => category,
          'created_at' => item['created_at'].to_i
        }

        if item['buyer_id'] != 0
          buyer = user_list.select{|seller| seller['id'] == item['buyer_id']}.first
          if buyer.nil?
            db.query('ROLLBACK')
            halt_with_error 404, 'buyer not found'
          end

          item_detail['buyer_id'] = item['buyer_id']
          item_detail['buyey'] = buyer
        end

        transaction_evidence = db.xquery('SELECT * FROM `transaction_evidences` WHERE `item_id` = ?', item['id']).first
        unless transaction_evidence.nil?
          shipping = db.xquery('SELECT * FROM `shippings` WHERE `transaction_evidence_id` = ?', transaction_evidence['id']).first
          if shipping.nil?
            db.query('ROLLBACK')
            halt_with_error 404, 'shipping not found'
          end

          ssr = begin
            api_client.shipment_status(get_shipment_service_url, 'reserve_id' => shipping['reserve_id'])
          rescue
            db.query('ROLLBACK')
            halt_with_error 500, 'failed to request to shipment service'
          end

          item_detail['transaction_evidence_id'] = transaction_evidence['id']
          item_detail['transaction_evidence_status'] = transaction_evidence['status']
          item_detail['shipping_status'] = ssr['status']
        end

        item_detail
      end

      db.query('COMMIT')

      has_next = false
      if item_details.length > TRANSACTIONS_PER_PAGE
        has_next = true
        item_details = item_details[0, TRANSACTIONS_PER_PAGE]
      end

      response = {
        'items' => item_details,
        'has_next' => has_next
      }

      response.to_json
    end