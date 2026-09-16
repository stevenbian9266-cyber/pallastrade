module PallasTrade
  module Api
    module V3
      module Store
        # 评论「有用」投票（F-5, PRD-20260916-catalog-batch-f5-helpful-vote）。
        #
        #   POST   /api/v3/store/reviews/:review_id/helpful_vote  标记有用（幂等）
        #   DELETE /api/v3/store/reviews/:review_id/helpful_vote  撤销（幂等）
        #
        # 两个动作都要求 customer JWT，并返回**权威状态**（票数 + 本人是否已投），
        # 前台因此不需要猜测点击是否落地；重复请求不会抬高计数（唯一索引兜底）。
        class ReviewHelpfulVotesController < Store::BaseController
          prepend_before_action :require_authentication!

          # POST /api/v3/store/reviews/:review_id/helpful_vote
          def create
            review = find_review!
            return if performed?

            # 给自己投票不是信号，是刷分。
            if review.user_id == current_user.id
              render_error(code: 'own_review_vote_forbidden', message: 'cannot vote for your own review', status: 422)
              return
            end

            vote = review.helpful_votes.find_or_initialize_by(user_id: current_user.id)
            vote.store_id = current_store.id
            if vote.new_record? && !vote.save
              render_errors(vote.errors)
              return
            end

            render_state(review)
          rescue ActiveRecord::RecordNotUnique
            # 并发双击：唯一索引已经记下这一票，按当前状态回答即可（幂等）。
            render_state(PallasTrade::Review.find(vote_review_id))
          end

          # DELETE /api/v3/store/reviews/:review_id/helpful_vote
          def destroy
            review = find_review!
            return if performed?

            review.helpful_votes.where(user_id: current_user.id).destroy_all

            render_state(review)
          end

          private

          # 只能对「读者看得到的东西」投票：未审核/已拒绝的评论对外不存在（404）。
          def find_review!
            current_store.reviews.approved.find_by_param!(params[:review_id])
          rescue ActiveRecord::RecordNotFound
            render_error(code: ERROR_CODES[:record_not_found], message: 'review not found', status: :not_found)
            nil
          end

          def vote_review_id
            PallasTrade::PrefixedId.decode_prefixed_id(params[:review_id])
          end

          def render_state(review)
            review.reload # counter cache 由数据层维护，这里取权威值

            render json: {
              data: {
                id: review.prefixed_id,
                type: 'review_helpful_vote',
                attributes: {
                  review_id: review.prefixed_id,
                  helpful_votes_count: review.helpful_votes_count,
                  helpful_voted: review.helpful_votes.exists?(user_id: current_user.id)
                }
              }
            }
          end
        end
      end
    end
  end
end
