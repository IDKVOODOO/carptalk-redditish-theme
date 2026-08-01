import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { get } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";

import ShareTopicModal from "discourse/components/modal/share-topic";
import PluginOutlet from "discourse/components/plugin-outlet";
import TopicExcerpt from "discourse/components/topic-list/topic-excerpt";
import TopicLink from "discourse/components/topic-list/topic-link";
import UnreadIndicator from "discourse/components/topic-list/unread-indicator";
import TopicPostBadges from "discourse/components/topic-post-badges";
import TopicStatus from "discourse/components/topic-status";
import categoryLink from "discourse/helpers/category-link";
import icon from "discourse/helpers/d-icon";
import discourseTags from "discourse/helpers/discourse-tags";
import formatDate from "discourse/helpers/format-date";
import lazyHash from "discourse/helpers/lazy-hash";
import topicFeaturedLink from "discourse/helpers/topic-featured-link";
import { ajax } from "discourse/lib/ajax";
import { wantsNewWindow } from "discourse/lib/intercept-click";
import { i18n } from "discourse-i18n";

export default class Item extends Component {
  @service currentUser;
  @service modal;

  @tracked likeLoading = false;
  @tracked likeStateLoaded = false;
  @tracked topicLiked = false;
  @tracked firstPostId = null;
  @tracked localLikeCount = null;

  get newDotText() {
    return this.currentUser?.trust_level > 0
      ? ""
      : i18n("filters.new.lower_title");
  }

  get displayedLikeCount() {
    if (this.localLikeCount !== null) {
      return this.localLikeCount;
    }

    return Number(this.args.outletArgs.topic.like_count || 0);
  }

  get showLikeButton() {
    const topicOwner =
      this.args.outletArgs.topic.posters?.[0]?.user;

    if (!this.currentUser || !topicOwner) {
      return false;
    }

    if (topicOwner.id && this.currentUser.id) {
      return this.currentUser.id !== topicOwner.id;
    }

    return this.currentUser.username !== topicOwner.username;
  }

  @action
  onTitleFocus(event) {
    event.target.closest(".topic-list-item").classList.add("selected");
  }

  @action
  onTitleBlur(event) {
    event.target.closest(".topic-list-item").classList.remove("selected");
  }

  @action
  openTopic(event) {
    if (
      event.target.closest(".card-like-button") ||
      (event.target.nodeName === "A" && !event.target.closest(".raw-link")) ||
      event.target.closest(".badge-wrapper")
    ) {
      return;
    }

    const { navigateToTopic, topic } = this.args.outletArgs;

    if (wantsNewWindow(event)) {
      window.open(topic.lastUnreadUrl, "_blank");
    } else {
      navigateToTopic(topic, topic.lastUnreadUrl);
    }
  }

  @action
  share(event) {
    event.stopPropagation();

    this.modal.show(ShareTopicModal, {
      model: { topic: this.args.outletArgs.topic },
    });
  }

  async loadLikeState() {
    if (this.likeStateLoaded) {
      return;
    }

    const topic = this.args.outletArgs.topic;
    const response = await ajax(`/t/${topic.id}.json`);

    const firstPost = response.post_stream?.posts?.find(
      (post) => post.post_number === 1
    );

    if (!firstPost) {
      throw new Error("Unable to find the first post");
    }

    const likeAction = firstPost.actions_summary?.find(
      (actionSummary) => actionSummary.id === 2
    );

    this.firstPostId = firstPost.id;
    this.topicLiked = Boolean(likeAction?.acted);
    this.localLikeCount = Number(
      firstPost.like_count ?? topic.like_count ?? 0
    );
    this.likeStateLoaded = true;
  }

  @action
  async toggleTopicLike(event) {
    event.preventDefault();
    event.stopPropagation();

    if (!this.currentUser || this.likeLoading) {
      return;
    }

    this.likeLoading = true;

    try {
      await this.loadLikeState();

      if (this.topicLiked) {
        await ajax(`/post_actions/${this.firstPostId}.json`, {
          type: "DELETE",
          data: {
            post_action_type_id: 2,
          },
        });

        this.topicLiked = false;
        this.localLikeCount = Math.max(0, this.displayedLikeCount - 1);
      } else {
        await ajax("/post_actions.json", {
          type: "POST",
          data: {
            id: this.firstPostId,
            post_action_type_id: 2,
          },
        });

        this.topicLiked = true;
        this.localLikeCount = this.displayedLikeCount + 1;
      }
    } catch (error) {
      this.likeStateLoaded = false;

      // eslint-disable-next-line no-console
      console.error("Unable to toggle topic like", error);
    } finally {
      this.likeLoading = false;
    }
  }

  <template>
    {{! template-lint-disable no-invalid-interactive }}
    <div {{on "click" this.openTopic}} class="custom-topic-layout">
      <div class="custom-topic-layout_meta">
        {{#unless @outletArgs.hideCategory}}
          {{#unless @outletArgs.topic.isPinnedUncategorized}}
            <PluginOutlet
              @name="topic-list-before-category"
              @outletArgs={{lazyHash topic=@outletArgs.topic}}
            />

            {{categoryLink @outletArgs.topic.category}}

            <span class="bullet-separator">&bull;</span>
          {{/unless}}
        {{/unless}}

        <span class="custom-topic-layout_meta-posted">
          <span class="custom-topic-layout_meta-posted-by">
            {{i18n (themePrefix "posted_by")}}
          </span>

          <a
            data-user-card={{get @outletArgs "topic.posters.0.user.username"}}
            href="/u/{{get @outletArgs 'topic.posters.0.user.username'}}"
          >
            @{{get @outletArgs "topic.posters.0.user.username"}}
          </a>

          {{formatDate
            @outletArgs.topic.createdAt
            format="medium"
            noTitle="true"
            leaveAgo="true"
          }}
        </span>
      </div>

      <h2 class="link-top-line">
        <TopicStatus @topic={{@outletArgs.topic}} />

        <TopicLink
          {{on "focus" this.onTitleFocus}}
          {{on "blur" this.onTitleBlur}}
          @topic={{@outletArgs.topic}}
          class="raw-link raw-topic-link"
        />

        {{#if @outletArgs.topic.featured_link}}
          {{topicFeaturedLink @outletArgs.topic}}
        {{/if}}

        <PluginOutlet
          @name="topic-list-after-title"
          @outletArgs={{lazyHash topic=@outletArgs.topic}}
        />

        <UnreadIndicator @topic={{@outletArgs.topic}} />

        {{#if @outletArgs.showTopicPostBadges}}
          <TopicPostBadges
            @unreadPosts={{@outletArgs.topic.unread_posts}}
            @unseen={{@outletArgs.topic.unseen}}
            @newDotText={{this.newDotText}}
            @url={{@outletArgs.topic.lastUnreadUrl}}
          />
        {{/if}}
      </h2>

      <div class="link-bottom-line">
        {{discourseTags
          @outletArgs.topic
          mode="list"
          tagsForUser=@outletArgs.tagsForUser
        }}
      </div>

      {{#if @outletArgs.topic.thumbnails}}
        <div class="custom-topic-layout_image">
          <img
            height={{get @outletArgs "topic.thumbnails.0.height"}}
            width={{get @outletArgs "topic.thumbnails.0.width"}}
            src={{get @outletArgs "topic.thumbnails.0.url"}}
          />
        </div>
      {{/if}}

      {{#unless @outletArgs.topic.thumbnails}}
        <div class="custom-topic-layout_excerpt">
          <TopicExcerpt @topic={{@outletArgs.topic}} />
        </div>
      {{/unless}}

      <div class="custom-topic-layout_bottom-bar">
        {{#if settings.show_like_count}}
          <span class="like-count">
            {{icon "heart"}}
            {{this.displayedLikeCount}}
            {{i18n "likes"}}
          </span>
        {{/if}}

        <span class="reply-count">
          {{icon "reply"}}
          {{@outletArgs.topic.replyCount}}
          {{i18n "replies"}}
        </span>

        {{! template-lint-disable no-invalid-interactive }}
        <span {{on "click" this.share}} class="share-toggle">
          {{icon "link"}}
          {{i18n "post.quote_share"}}
        </span>

        {{#if this.showLikeButton}}
          <button
            type="button"
            class="card-like-button {{if this.topicLiked 'is-liked'}}"
            disabled={{this.likeLoading}}
            aria-label={{if
              this.topicLiked
              "Unlike this topic"
              "Like this topic"
            }}
            title={{if this.topicLiked "Unlike" "Like"}}
            {{on "click" this.toggleTopicLike}}
          >
            {{icon (if this.topicLiked "d-liked" "d-unliked")}}

            <span>
              {{if this.topicLiked "Liked" "Like this post"}}
            </span>
          </button>
        {{/if}}
      </div>
    </div>
  </template>
}
